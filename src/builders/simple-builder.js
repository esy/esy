/**
 * @flow
 */

import type {BuildTask, BuildConfig, BuildSandbox} from '../types';

import createLogger from 'debug';
import * as path from 'path';
import * as os from 'os';
import * as nodefs from 'fs';

import {PromiseQueue} from '../lib/Promise';
import * as fs from '../lib/fs';

import * as Graph from '../graph';
import * as Config from '../build-config';
import {endWritableStream, interleaveStreams, writeIntoStream} from '../util';
import {renderEnv, renderSandboxSbConfig, rewritePathInFile, exec} from './util';

const INSTALL_DIRS = ['lib', 'bin', 'sbin', 'man', 'doc', 'share', 'stublibs', 'etc'];
const BUILD_DIRS = ['_esy'];
const PATHS_TO_IGNORE = [
  Config.STORE_BUILD_TREE,
  Config.STORE_INSTALL_TREE,
  Config.STORE_STAGE_TREE,
  'node_modules',
];
const IGNORE_FOR_CHECKSUM = [
  'node_modules',
  '_esy',
  Config.STORE_BUILD_TREE,
  Config.STORE_INSTALL_TREE,
  Config.STORE_STAGE_TREE,
];

const NUM_CPUS = os.cpus().length;

type SuccessBuildState = {
  state: 'success',
  timeEllapsed: ?number,
  cached: boolean,
  forced: boolean,
};
type FailureBuildState = {state: 'failure', error: Error};
type InProgressBuildState = {state: 'in-progress'};

export type BuildTaskState = SuccessBuildState | FailureBuildState | InProgressBuildState;
export type FinalBuildState = SuccessBuildState | FailureBuildState;

export const build = async (
  task: BuildTask,
  sandbox: BuildSandbox,
  config: BuildConfig,
  onTaskStatus: (task: BuildTask, status: BuildTaskState) => *,
) => {
  await Promise.all([initStore(config.storePath), initStore(config.localStorePath)]);

  const buildQueue = new PromiseQueue({concurrency: NUM_CPUS});
  const taskInProgress = new Map();

  function isSpecExistsInStore(spec) {
    return fs.exists(config.getFinalInstallPath(spec));
  }

  async function calculateSourceChecksum(spec) {
    const ignoreForChecksum = new Set(
      IGNORE_FOR_CHECKSUM.map(s => config.getSourcePath(spec, s)),
    );
    const sourcePath = await fs.realpath(config.getSourcePath(spec));
    return await fs.calculateMtimeChecksum(sourcePath, {
      ignore: name => ignoreForChecksum.has(name),
    });
  }

  async function readSourceChecksum(spec) {
    const checksumFilename = config.getBuildPath(spec, '_esy', 'checksum');
    return (await fs.exists(checksumFilename))
      ? (await fs.readFile(checksumFilename)).trim()
      : null;
  }

  async function writeStoreChecksum(spec, checksum) {
    const checksumFilename = config.getBuildPath(spec, '_esy', 'checksum');
    await fs.writeFile(checksumFilename, checksum.trim());
  }

  async function performBuildMemoized(
    task: BuildTask,
    forced = false,
  ): Promise<FinalBuildState> {
    const {spec} = task;
    const cachedSuccessStatus = {
      state: 'success',
      timeEllapsed: null,
      cached: true,
      forced: false,
    };
    let inProgress = taskInProgress.get(task.id);
    if (inProgress == null) {
      // if build task is forced (for example by one of the deps updated)
      if (forced) {
        if (task.spec.shouldBePersisted) {
          inProgress = performBuildWithStatusReport(task, true);
        } else {
          inProgress = performBuildWithStatusReport(task, true).then(async result => {
            const currentChecksum = await calculateSourceChecksum(spec);
            await writeStoreChecksum(spec, currentChecksum);
            return result;
          });
        }
      } else {
        const isInStore = await isSpecExistsInStore(spec);
        if (spec.shouldBePersisted && isInStore) {
          onTaskStatus(task, cachedSuccessStatus);
          inProgress = Promise.resolve(cachedSuccessStatus);
        } else if (!spec.shouldBePersisted) {
          const currentChecksum = await calculateSourceChecksum(spec);
          if (isInStore && (await readSourceChecksum(spec)) === currentChecksum) {
            onTaskStatus(task, cachedSuccessStatus);
            inProgress = Promise.resolve(cachedSuccessStatus);
          } else {
            inProgress = performBuildWithStatusReport(task, true).then(async result => {
              await writeStoreChecksum(spec, currentChecksum);
              return result;
            });
          }
        } else {
          inProgress = performBuildWithStatusReport(task);
        }
      }
      taskInProgress.set(task.id, inProgress);
    }
    return inProgress;
  }

  function performBuildWithStatusReport(task, forced = false): Promise<FinalBuildState> {
    return buildQueue.add(async () => {
      onTaskStatus(task, {state: 'in-progress'});
      const startTime = Date.now();
      try {
        await performBuild(task, config, sandbox);
      } catch (error) {
        const state = {state: 'failure', error};
        onTaskStatus(task, state);
        return state;
      }
      const endTime = Date.now();
      const timeEllapsed = endTime - startTime;
      const state = {state: 'success', timeEllapsed, cached: false, forced};
      onTaskStatus(task, state);
      return state;
    });
  }

  await Graph.topologicalFold(
    task,
    (directDependencies: Map<string, Promise<FinalBuildState>>, allDependencies, task) =>
      Promise.all(directDependencies.values()).then(states => {
        if (states.some(state => state.state === 'failure')) {
          return Promise.resolve({
            state: 'failure',
            error: new Error('dependencies are not built'),
          });
        } else if (states.some(state => state.state === 'success' && state.forced)) {
          return performBuildMemoized(task, true);
        } else {
          return performBuildMemoized(task);
        }
      }),
  );
};

async function performBuild(
  task: BuildTask,
  config: BuildConfig,
  sandbox: BuildSandbox,
): Promise<void> {
  const rootPath = config.getRootPath(task.spec);
  const installPath = config.getInstallPath(task.spec);
  const finalInstallPath = config.getFinalInstallPath(task.spec);
  const buildPath = config.getBuildPath(task.spec);

  const log = createLogger(`esy:simple-builder:${task.spec.name}`);

  log('starting build');

  log('removing prev destination directories (if exist)');
  await Promise.all([
    fs.rmdir(finalInstallPath),
    fs.rmdir(installPath),
    fs.rmdir(buildPath),
  ]);

  log('creating destination directories');
  await Promise.all([
    ...BUILD_DIRS.map(p => fs.mkdirp(config.getBuildPath(task.spec, p))),
    ...INSTALL_DIRS.map(p => fs.mkdirp(config.getInstallPath(task.spec, p))),
  ]);

  if (task.spec === sandbox.root) {
    await fs.symlink(
      buildPath,
      path.join(config.sandboxPath, task.spec.sourcePath, '_build'),
    );
  }

  if (task.spec.mutatesSourcePath) {
    log('build mutates source directory, rsyncing sources to $cur__target_dir');
    await fs.copydir(
      path.join(config.sandboxPath, task.spec.sourcePath),
      config.getBuildPath(task.spec),
      {
        exclude: PATHS_TO_IGNORE.map(p =>
          path.join(config.sandboxPath, task.spec.sourcePath, p),
        ),
      },
    );
  }

  const envForExec = {};
  for (const item of task.env.values()) {
    envForExec[item.name] = item.value;
  }

  log('placing _esy/env');
  const envPath = path.join(buildPath, '_esy', 'env');
  await fs.writeFile(envPath, renderEnv(task.env), 'utf8');

  log('placing _esy/sandbox.conf');
  const darwinSandboxConfig = path.join(buildPath, '_esy', 'sandbox.sb');
  const tempDirs = await Promise.all(
    ['/tmp', process.env.TMPDIR].filter(Boolean).map(p => fs.realpath(p)),
  );
  await fs.writeFile(
    darwinSandboxConfig,
    renderSandboxSbConfig(task.spec, config, {
      allowFileWrite: tempDirs,
    }),
    'utf8',
  );

  if (task.command != null) {
    const commandList = task.command;
    const logFilename = config.getBuildPath(task.spec, '_esy', 'log');
    const logStream = nodefs.createWriteStream(logFilename);
    for (let i = 0; i < commandList.length; i++) {
      const {command, renderedCommand} = commandList[i];
      log(`executing: ${command}`);
      let sandboxedCommand = renderedCommand;
      if (process.platform === 'darwin') {
        sandboxedCommand = `sandbox-exec -f ${darwinSandboxConfig} -- ${renderedCommand}`;
      }

      await writeIntoStream(logStream, `### ORIGINAL COMMAND: ${renderedCommand}\n`);
      await writeIntoStream(logStream, `### RENDERED COMMAND: ${renderedCommand}\n`);

      const execution = await exec(sandboxedCommand, {
        cwd: rootPath,
        env: envForExec,
        maxBuffer: Infinity,
      });
      // TODO: we need line-buffering here possibly?
      interleaveStreams(
        execution.process.stdout,
        execution.process.stderr,
      ).pipe(logStream, {end: false});
      const {code} = await execution.exit;
      if (code !== 0) {
        throw new BuildTaskError(task, logFilename);
      }
    }
    await endWritableStream(logStream);

    log('rewriting paths in build artefacts');
    const rewriteQueue = new PromiseQueue({concurrency: 20});
    const files = await fs.walk(config.getInstallPath(task.spec));
    await Promise.all(
      files.map(file =>
        rewriteQueue.add(() =>
          rewritePathInFile(file.absolute, installPath, finalInstallPath),
        ),
      ),
    );
  }

  log('finalizing build');

  await fs.rename(installPath, finalInstallPath);

  if (task.spec === sandbox.root) {
    await fs.symlink(
      finalInstallPath,
      path.join(config.sandboxPath, task.spec.sourcePath, '_install'),
    );
  }
}

async function initStore(storePath) {
  await Promise.all(
    [Config.STORE_BUILD_TREE, Config.STORE_INSTALL_TREE, Config.STORE_STAGE_TREE].map(p =>
      fs.mkdirp(path.join(storePath, p)),
    ),
  );
}

class BuildTaskError extends Error {
  logFilename: string;
  task: BuildTask;

  constructor(task: BuildTask, logFilename: string) {
    super(`Build failed: ${task.spec.name}`);
    this.task = task;
    this.logFilename = logFilename;
  }
}
