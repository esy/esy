/**
 * @flow
 */

import type {BuildTask, BuildSpec, Store, Config, BuildSandbox} from '../types';

import invariant from 'invariant';
import createLogger from 'debug';
import * as os from 'os';
import * as nodefs from 'fs';

import {PromiseQueue} from '../lib/Promise';
import * as path from '../lib/path';
import * as fs from '../lib/fs';
import * as child from '../lib/child_process';
import {fixupErrorSubclassing} from '../lib/lang';

import * as Graph from '../graph';
import {endWritableStream, interleaveStreams, writeIntoStream} from '../util';
import {renderEnv, renderSandboxSbConfig, rewritePathInFile, exec} from './util';
import {
  BUILD_TREE_SYMLINK,
  INSTALL_TREE_SYMLINK,
  STORE_BUILD_TREE,
  STORE_STAGE_TREE,
  STORE_INSTALL_TREE,
} from '../constants';

type BuildStateSuccess = {
  state: 'success',
  timeEllapsed: ?number,
  cached: boolean,
  forced: boolean,
};

type BuildStateFailure = {
  state: 'failure',
  error: BuildError,
};

type BuildStateInpProgress = {
  state: 'in-progress',
};

export type BuildState = BuildStateSuccess | BuildStateFailure | BuildStateInpProgress;
export type FinalBuildState = BuildStateSuccess | BuildStateFailure;

const INSTALL_DIR_STRUCTURE = [
  'lib',
  'bin',
  'sbin',
  'man',
  'doc',
  'share',
  'stublibs',
  'etc',
];
const BUILD_DIR_STRUCTURE = ['_esy'];

const IGNORE_FOR_BUILD = [
  BUILD_TREE_SYMLINK,
  INSTALL_TREE_SYMLINK,
  '_release',
  'node_modules',
];
const IGNORE_FOR_CHECKSUM = [
  '_esy',
  BUILD_TREE_SYMLINK,
  INSTALL_TREE_SYMLINK,
  '_release',
  'node_modules',
];

const NUM_CPUS = os.cpus().length;

const BUILD_STATE_CACHED_SUCCESS = {
  state: 'success',
  timeEllapsed: null,
  cached: true,
  forced: false,
};

/**
 * Build the entire sandbox starting from the `rootTask`.
 */
export const build = async (
  rootTask: BuildTask,
  sandbox: BuildSandbox,
  config: Config<path.AbsolutePath>,
  onBuildStateChange: (task: BuildTask, state: BuildState) => *,
) => {
  await Promise.all([initStore(config.store), initStore(config.localStore)]);
  const performBuild = createBuilder(sandbox, config, onBuildStateChange);

  return await Graph.topologicalFold(
    rootTask,
    async (
      directDependencies: Map<string, Promise<FinalBuildState>>,
      allDependencies,
      task,
    ) => {
      const states = await Promise.all(directDependencies.values());

      const failures = [];
      for (const s of states) {
        if (s.state === 'failure') {
          failures.push(s);
        }
      }

      if (failures.length > 0) {
        // shortcut if some of the deps failed
        return {
          state: 'failure',
          error: new DependencyBuildError(task, failures.map(state => state.error)),
        };
      } else if (states.some(state => state.state === 'success' && state.forced)) {
        // if some of the deps were forced then force the rebuild too
        return performBuild(task, true);
      } else {
        return performBuild(task);
      }
    },
  );
};

/**
 * Build all the sandbox but not the `rootTask`.
 */
export const buildDependencies = async (
  rootTask: BuildTask,
  sandbox: BuildSandbox,
  config: Config<path.AbsolutePath>,
  onBuildStateChange: (task: BuildTask, status: BuildState) => *,
) => {
  await Promise.all([initStore(config.store), initStore(config.localStore)]);
  const performBuild = createBuilder(sandbox, config, onBuildStateChange);

  return await Graph.topologicalFold(
    rootTask,
    async (
      directDependencies: Map<string, Promise<FinalBuildState>>,
      allDependencies,
      task,
    ) => {
      const states = await Promise.all(directDependencies.values());

      const failures = [];
      for (const s of states) {
        if (s.state === 'failure') {
          failures.push(s);
        }
      }

      if (failures.length > 0) {
        // shortcut if some of the deps failed
        return {
          state: 'failure',
          error: new DependencyBuildError(task, failures.map(state => state.error)),
        };
      } else {
        if (task === rootTask) {
          return BUILD_STATE_CACHED_SUCCESS;
        } else if (states.some(state => state.state === 'success' && state.forced)) {
          // if some of the deps were forced then force the rebuild too
          return performBuild(task, true);
        } else {
          return performBuild(task);
        }
      }
    },
  );
};

const createBuilder = (
  sandbox: BuildSandbox,
  config: Config<path.AbsolutePath>,
  onBuildStateChange: (task: BuildTask, status: BuildState) => *,
) => {
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

  async function performBuildOrRelocate(task): Promise<void> {
    for (const store of config.readOnlyStores) {
      if (await store.has(task.spec)) {
        await relocateBuild(store, config.store, task.spec);
        return;
      }
    }
    await performBuild(task, config, sandbox);
  }

  function performBuildWithStatusReport(task, forced = false): Promise<FinalBuildState> {
    return buildQueue.add(async () => {
      onBuildStateChange(task, {state: 'in-progress'});
      const startTime = Date.now();
      try {
        await performBuildOrRelocate(task);
      } catch (error) {
        if (!(error instanceof BuildError)) {
          error = new InternalBuildError(task, error);
        }
        const state = {
          state: 'failure',
          error,
        };
        onBuildStateChange(task, state);
        return state;
      }
      const endTime = Date.now();
      const timeEllapsed = endTime - startTime;
      const state = {state: 'success', timeEllapsed, cached: false, forced};
      onBuildStateChange(task, state);
      return state;
    });
  }

  async function performBuildMemoized(
    task: BuildTask,
    forced: boolean = false,
  ): Promise<FinalBuildState> {
    const {spec} = task;
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
          onBuildStateChange(task, BUILD_STATE_CACHED_SUCCESS);
          inProgress = Promise.resolve(BUILD_STATE_CACHED_SUCCESS);
        } else if (!spec.shouldBePersisted) {
          const currentChecksum = await calculateSourceChecksum(spec);
          if (isInStore && (await readSourceChecksum(spec)) === currentChecksum) {
            onBuildStateChange(task, BUILD_STATE_CACHED_SUCCESS);
            inProgress = Promise.resolve(BUILD_STATE_CACHED_SUCCESS);
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

  return performBuildMemoized;
};

type BuildDriver = {
  rootPath: string,
  installPath: string,
  finalInstallPath: string,
  buildPath: string,
  log: string => void,

  executeCommand(command: string, renderedCommand?: string): Promise<void>,
  spawnInteractiveProcess(command: string, args: string[]): Promise<void>,
};

export async function withBuildDriver(
  task: BuildTask,
  config: Config<path.AbsolutePath>,
  sandbox: BuildSandbox,
  f: BuildDriver => Promise<void>,
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
    ...BUILD_DIR_STRUCTURE.map(p => fs.mkdirp(config.getBuildPath(task.spec, p))),
    ...INSTALL_DIR_STRUCTURE.map(p => fs.mkdirp(config.getInstallPath(task.spec, p))),
  ]);

  if (task.spec.mutatesSourcePath) {
    log('build mutates source directory, rsyncing sources to $cur__target_dir');
    await fs.copydir(
      path.join(config.sandboxPath, task.spec.sourcePath),
      config.getBuildPath(task.spec),
      {
        exclude: IGNORE_FOR_BUILD.map(p =>
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
  const tempDirs: Array<Promise<?string>> = ['/tmp', process.env.TMPDIR]
    .filter(Boolean)
    .map(p => fs.realpath(p));
  await fs.writeFile(
    darwinSandboxConfig,
    renderSandboxSbConfig(task.spec, config, {
      allowFileWrite: await Promise.all(tempDirs),
    }),
    'utf8',
  );

  const logFilename = config.getBuildPath(task.spec, '_esy', 'log');
  const logStream = nodefs.createWriteStream(logFilename);

  const executeCommand = async (command: string, renderedCommand?: string = command) => {
    log(`executing: ${command}`);
    let sandboxedCommand = renderedCommand;
    if (process.platform === 'darwin') {
      sandboxedCommand = `sandbox-exec -f ${darwinSandboxConfig} -- ${renderedCommand}`;
    }

    await writeIntoStream(logStream, `### ORIGINAL COMMAND: ${command}\n`);
    await writeIntoStream(logStream, `### RENDERED COMMAND: ${renderedCommand}\n`);

    const execution = await exec(sandboxedCommand, {
      cwd: rootPath,
      env: envForExec,
      maxBuffer: Infinity,
    });
    // TODO: we need line-buffering here possibly?
    interleaveStreams(execution.process.stdout, execution.process.stderr).pipe(
      logStream,
      {end: false},
    );
    const {code} = await execution.exit;
    if (code !== 0) {
      throw new BuildCommandError(task, command, logFilename);
    }
  };

  const spawnInteractiveProcess = async (command: string, args: Array<string>) => {
    log(`executing interactively: ${command}`);

    if (process.platform === 'darwin') {
      args = ['-f', darwinSandboxConfig, '--', command].concat(args);
      command = 'sandbox-exec';
    }

    try {
      await child.spawn(command, args, {
        cwd: rootPath,
        env: envForExec,
        stdio: 'inherit',
      });
    } catch (err) {
      throw new InteractiveCommandError(task);
    }
  };

  const buildDriver: BuildDriver = {
    rootPath,
    installPath,
    finalInstallPath,
    buildPath,

    executeCommand,
    spawnInteractiveProcess,

    log,
  };

  try {
    await f(buildDriver);
  } finally {
    await endWritableStream(logStream);
  }
}

async function performBuild(
  task: BuildTask,
  config: Config<path.AbsolutePath>,
  sandbox: BuildSandbox,
): Promise<void> {
  const sandboxRootBuildTreeSymlink = path.join(config.sandboxPath, BUILD_TREE_SYMLINK);
  const sandboxRootInstallTreeSymlink = path.join(
    config.sandboxPath,
    INSTALL_TREE_SYMLINK,
  );

  async function executeBuildCommands(driver: BuildDriver) {
    // For top level build we need to remove build tree symlink and install tree
    // symlink as in case of non mutating build it can interfere with the build
    // itself. In case of mutating build they still be ignore then copying sources
    // of to `$cur__target_dir`.
    if (task.spec === sandbox.root && !task.spec.mutatesSourcePath) {
      await Promise.all([
        unlinkOrRemove(sandboxRootBuildTreeSymlink),
        unlinkOrRemove(sandboxRootInstallTreeSymlink),
      ]);
    }

    let buildSucceeded = false;

    try {
      if (task.command != null) {
        const commandList = task.command;
        for (const {command, renderedCommand} of task.command) {
          await driver.executeCommand(command, renderedCommand);
        }

        driver.log('rewriting paths in build artefacts');
        await rewritePaths(
          config.getInstallPath(task.spec),
          driver.installPath,
          driver.finalInstallPath,
        );
      }

      driver.log('finalizing build');
      await fs.rename(driver.installPath, driver.finalInstallPath);

      buildSucceeded = true;
    } finally {
      if (task.spec === sandbox.root) {
        // Those can be either created by esy or by previous build process so we
        // forcefully remove them.
        await Promise.all([
          unlinkOrRemove(sandboxRootBuildTreeSymlink),
          unlinkOrRemove(sandboxRootInstallTreeSymlink),
        ]);
        await Promise.all([
          fs.symlink(driver.buildPath, sandboxRootBuildTreeSymlink),
          buildSucceeded &&
            fs.symlink(driver.finalInstallPath, sandboxRootInstallTreeSymlink),
        ]);
      }
    }
  }

  await withBuildDriver(task, config, sandbox, executeBuildCommands);
}

async function initStore(store: Store<path.AbsolutePath>) {
  await Promise.all(
    [STORE_BUILD_TREE, STORE_INSTALL_TREE, STORE_STAGE_TREE].map(p =>
      fs.mkdirp(path.join(store.path, path.concrete(p))),
    ),
  );
}

async function unlinkOrRemove(p) {
  let stats = null;
  try {
    stats = await fs.lstat(p);
  } catch (err) {
    if (err.code === 'ENOENT') {
      return;
    }
    throw err;
  }
  if (stats != null) {
    if (stats.isSymbolicLink()) {
      await fs.unlink(p);
    } else {
      await fs.rmdir(p);
    }
  }
}

async function rewritePaths(path, from, to) {
  const rewriteQueue = new PromiseQueue({concurrency: 20});
  const files = await fs.walk(path);
  await Promise.all(
    files.map(file => rewriteQueue.add(() => rewritePathInFile(file.absolute, from, to))),
  );
}

async function relocateBuild(
  from: Store<path.AbsolutePath>,
  to: Store<path.AbsolutePath>,
  build: BuildSpec,
): Promise<void> {
  invariant(
    from.path.length === to.path.length,
    'Cannot relocate between stores of different path length: %s and %s',
    from.path,
    to.path,
  );
  const stage = await fs.mkdtemp(`reloc-build-${build.id}`);
  const originPath = from.getPath(STORE_INSTALL_TREE, build);
  const destPath = to.getPath(STORE_INSTALL_TREE, build);
  const stagePath = path.join(stage, STORE_INSTALL_TREE);
  try {
    await fs.copydir(originPath, stagePath);
    await rewritePaths(stagePath, from.path, to.path);
    await fs.mkdirp(path.dirname(destPath));
  } finally {
    fs.rmdir(stage);
  }
  await fs.rename(stagePath, destPath);
}

/**
 * Base class for build errors.
 */
export class BuildError extends Error {
  task: BuildTask;

  constructor(task: BuildTask) {
    super(`build error: ${task.spec.name}`);
    this.task = task;
    fixupErrorSubclassing(this, BuildError);
  }
}

/**
 * Build error due to erronous dependencies.
 */
export class DependencyBuildError extends BuildError {
  reasons: Array<BuildError>;

  constructor(task: BuildTask, reasons: Array<BuildError>) {
    super(task);
    this.reasons = reasons;
    fixupErrorSubclassing(this, DependencyBuildError);
  }
}

/**
 * Internal build error. A possible bug with Esy.
 */
export class InternalBuildError extends BuildError {
  error: Error;

  constructor(task: BuildTask, error: Error) {
    super(task);
    this.error = error;
    fixupErrorSubclassing(this, InternalBuildError);
  }
}

/**
 * Error happened during executing a build command.
 */
export class BuildCommandError extends BuildError {
  command: string;
  logFilename: string;

  constructor(task: BuildTask, command: string, logFilename: string) {
    super(task);
    this.command = command;
    this.logFilename = logFilename;
    fixupErrorSubclassing(this, BuildCommandError);
  }
}

/**
 * Error happened during executing an interactive command.
 */
export class InteractiveCommandError extends BuildError {
  task: BuildTask;

  constructor(task: BuildTask) {
    super(task);
    fixupErrorSubclassing(this, InteractiveCommandError);
  }
}

/**
 * Collect all build errors.
 */
export function collectBuildErrors(state: BuildStateFailure): Array<BuildError> {
  const errors = [];
  const seen = new Set();
  const queue = [state.error];

  while (queue.length > 0) {
    const error = queue.shift();
    if (error instanceof DependencyBuildError) {
      queue.push(...error.reasons);
    } else {
      if (!seen.has(error)) {
        seen.add(error);
        errors.push(error);
      }
    }
  }

  return errors;
}
