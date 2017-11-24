/**
 * @flow
 */

import type {BuildTask, BuildSpec, Store, Config, Sandbox} from '../types';

import invariant from 'invariant';
import createLogger from 'debug';
import * as os from 'os';
import * as nodefs from 'fs';
import jsonStableStringify from 'json-stable-stringify';

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
  CURRENT_ESY_EXECUTABLE,
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
  '_build', // this is needed b/c of buildType == '_build'
  '_release',
  'node_modules',
];
const IGNORE_FOR_MTIME = [
  '_esy',
  BUILD_TREE_SYMLINK,
  INSTALL_TREE_SYMLINK,
  '_release',
  'node_modules',
];

const BUILD_STATE_CACHED_SUCCESS = {
  state: 'success',
  timeEllapsed: null,
  cached: true,
  forced: false,
};

/**
 * Build the entire sandbox starting from the `rootTask`.
 */
export const build = async (rootTask: BuildTask, config: Config<path.AbsolutePath>) => {
  await initStores(config.store, config.localStore);

  // TODO: we need to know in advance how much builds will be performed, now we
  // approximate this by the total size of the bild graph
  const total = Graph.size(rootTask);
  const activitySet = config.reporter.activitySet(total, config.buildConcurrency);
  const performBuild = createBuilder(config, activitySet);

  const state = await Graph.topologicalFold(
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

  activitySet.end();

  return state;
};

/**
 * Build all the sandbox but not the `rootTask`.
 */
export const buildDependencies = async (
  rootTask: BuildTask,
  config: Config<path.AbsolutePath>,
) => {
  await initStores(config.store, config.localStore);

  // TODO: we need to know in advance how much builds will be performed, now we
  // approximate this by the total size of the bild graph
  const total = Graph.size(rootTask) - 1;
  const activitySet = config.reporter.activitySet(total, config.buildConcurrency);
  const performBuild = createBuilder(config, activitySet);

  const state = await Graph.topologicalFold(
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

  activitySet.end();

  return state;
};

const createBuilder = (config: Config<path.AbsolutePath>, activitySet) => {
  const buildQueue = new PromiseQueue({concurrency: config.buildConcurrency});
  const taskInProgress = new Map();

  function checkIfIsInStore(spec) {
    return fs.exists(config.getFinalInstallPath(spec));
  }

  async function findBuildMtime(spec) {
    const ignoreForMtime = new Set(
      IGNORE_FOR_MTIME.map(s => config.getSourcePath(spec, s)),
    );
    const sourcePath = config.getSourcePath(spec);
    return await fs.findMaxMtime(sourcePath, {
      ignore: name => ignoreForMtime.has(name),
    });
  }

  async function readBuildMtime(spec): Promise<number> {
    const checksumFilename = config.getBuildPath(spec, '_esy', 'mtime');
    return (await fs.exists(checksumFilename))
      ? parseInt(await fs.readFile(checksumFilename), 10)
      : -Infinity;
  }

  async function writeBuildMtime(spec, mtime: number) {
    const checksumFilename = config.getBuildPath(spec, '_esy', 'mtime');
    await fs.writeFile(checksumFilename, String(mtime));
  }

  async function performBuildOrImport(task, log, spinner): Promise<void> {
    for (const importPath of config.importPaths) {
      for (const basename of [task.spec.id, `${task.spec.id}.tar.gz`]) {
        const buildPath = path.join(importPath, basename);
        log(`testing for import: ${buildPath}`);
        if (await fs.exists(buildPath)) {
          log(`importing build: ${buildPath}`);
          await importBuild(config, buildPath);
          return;
        }
      }
    }
    await performBuild(task, config, spinner);
  }

  const acquiredSpinners = new Set();
  let buildNumber = 0;

  function acquireSpinner() {
    for (const spinner of activitySet.spinners) {
      if (!acquiredSpinners.has(spinner)) {
        acquiredSpinners.add(spinner);
        return spinner;
      }
    }
    return dummySpinner;
  }

  function freeSpinner(spinner) {
    spinner.clear();
    acquiredSpinners.delete(spinner);
  }

  function performBuildWithStatusReport(
    task,
    log,
    forced = false,
  ): Promise<FinalBuildState> {
    return buildQueue.add(async () => {
      buildNumber += 1;
      const spinner = acquireSpinner();
      spinner.setPrefix(buildNumber, `building ${task.spec.name}@${task.spec.version}`);
      const startTime = Date.now();
      try {
        await performBuildOrImport(task, log, spinner);
      } catch (error) {
        if (!(error instanceof BuildError)) {
          error = new InternalBuildError(task, error);
        }
        const state = {
          state: 'failure',
          error,
        };
        return state;
      }
      const endTime = Date.now();
      const timeEllapsed = endTime - startTime;
      const state = {state: 'success', timeEllapsed, cached: false, forced};
      freeSpinner(spinner);
      return state;
    });
  }

  async function performBuildMemoized(
    task: BuildTask,
    forced: boolean = false,
  ): Promise<FinalBuildState> {
    const log = createLogger(`esy:simple-builder:${task.spec.name}`);
    const {spec} = task;
    let inProgress = taskInProgress.get(task.id);
    if (inProgress == null) {
      // if build task is forced (for example by one of the deps updated)
      if (forced) {
        if (task.spec.sourceType === 'immutable') {
          inProgress = performBuildWithStatusReport(task, log, true);
        } else {
          inProgress = performBuildWithStatusReport(
            task,
            log,
            true,
          ).then(async result => {
            const maxMtime = await findBuildMtime(spec);
            log('saving build mtime:', maxMtime);
            await writeBuildMtime(spec, maxMtime);
            return result;
          });
        }
      } else {
        const isInStore = await checkIfIsInStore(spec);
        if (spec.sourceType === 'immutable' && isInStore) {
          //onBuildStateChange(task, BUILD_STATE_CACHED_SUCCESS);
          inProgress = Promise.resolve(BUILD_STATE_CACHED_SUCCESS);
        } else if (spec.sourceType !== 'immutable') {
          const buildMtime = await readBuildMtime(spec);
          const maxMtime = await findBuildMtime(spec);
          log('build mtime, current mtime:', buildMtime, maxMtime);
          if (isInStore && maxMtime <= buildMtime) {
            //onBuildStateChange(task, BUILD_STATE_CACHED_SUCCESS);
            inProgress = Promise.resolve(BUILD_STATE_CACHED_SUCCESS);
          } else {
            inProgress = performBuildWithStatusReport(
              task,
              log,
              true,
            ).then(async result => {
              log('saving build mtime:', maxMtime);
              await writeBuildMtime(spec, maxMtime);
              return result;
            });
          }
        } else {
          inProgress = performBuildWithStatusReport(task, log);
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
  f: BuildDriver => Promise<void>,
): Promise<void> {
  const rootPath = config.getRootPath(task.spec);
  const sourcePath = config.getSourcePath(task.spec);
  const installPath = config.getInstallPath(task.spec);
  const finalInstallPath = config.getFinalInstallPath(task.spec);
  const buildPath = config.getBuildPath(task.spec);
  const isRoot = task.spec.buildType === 'root';

  const log = createLogger(`esy:simple-builder:${task.spec.name}`);

  log('buildType', task.spec.buildType);
  log('sourceType', task.spec.sourceType);

  log('removing prev destination directories (if exist)');
  await Promise.all([fs.rmdir(finalInstallPath), fs.rmdir(installPath)]);

  log('creating destination directories');
  await Promise.all([
    ...BUILD_DIR_STRUCTURE.map(p => fs.mkdirp(config.getBuildPath(task.spec, p))),
    ...INSTALL_DIR_STRUCTURE.map(p => fs.mkdirp(config.getInstallPath(task.spec, p))),
  ]);

  const relocateSource = async () => {
    log('relocating sources to root path');
    await fs.copydir(sourcePath, rootPath, {
      exclude: IGNORE_FOR_BUILD.map(p => config.getSourcePath(task.spec, p)),
    });
  };

  const relocateBuildDir = async () => {
    const buildDir = config.getRootPath(task.spec, '_build');
    const buildTargetDir = config.getBuildPath(task.spec, '_build');
    const buildBackupDir = config.getBuildPath(task.spec, '_build.prev');
    await renameIfExists(buildDir, buildBackupDir);
    await renameIfExists(buildTargetDir, buildDir);
  };

  const relocateBuildDirComplete = async () => {
    const buildDir = config.getRootPath(task.spec, '_build');
    const buildTargetDir = config.getBuildPath(task.spec, '_build');
    const buildBackupDir = config.getBuildPath(task.spec, '_build.prev');
    await renameIfExists(buildDir, buildTargetDir);
    await renameIfExists(buildBackupDir, buildDir);
  };

  if (task.spec.buildType === 'in-source') {
    await relocateSource();
  } else if (task.spec.buildType === '_build') {
    if (task.spec.sourceType === 'immutable') {
      await relocateSource();
    } else if (task.spec.sourceType === 'transient') {
      await relocateBuildDir();
    } else if (task.spec.sourceType === 'root') {
      // nothing
    }
  } else if (task.spec.buildType === 'out-of-source') {
    // nothing
  }

  const envForExec = {};
  for (const item of task.env.values()) {
    envForExec[item.name] = item.value;
  }

  log('placing _esy/idInfo');
  const idInfoPath = path.join(buildPath, '_esy', 'idInfo');
  await fs.writeFile(idInfoPath, jsonStableStringify(task.spec.idInfo, {space: '  '}));

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
    await writeIntoStream(logStream, `### CWD: ${rootPath}\n`);

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
      throw new BuildCommandError(task, command, config.prettifyPath(logFilename));
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
    if (task.spec.buildType === 'in-source') {
      // nothing
    } else if (task.spec.buildType === '_build') {
      if (task.spec.sourceType === 'immutable') {
        // nothing
      } else if (task.spec.sourceType === 'transient') {
        await relocateBuildDirComplete();
      } else if (task.spec.sourceType === 'root') {
        // nothing
      }
    } else if (task.spec.buildType === 'out-of-source') {
      // nothing
    }

    await endWritableStream(logStream);
  }
}

async function performBuild(
  task: BuildTask,
  config: Config<path.AbsolutePath>,
  spinner,
): Promise<void> {
  const isRoot = task.spec.packagePath === '';
  const sandboxRootBuildTreeSymlink = path.join(config.sandboxPath, BUILD_TREE_SYMLINK);
  const sandboxRootInstallTreeSymlink = path.join(
    config.sandboxPath,
    INSTALL_TREE_SYMLINK,
  );
  const symlinksAreNeeded = isRoot && task.spec.buildType !== '_build';

  async function executeBuildCommands(driver: BuildDriver) {
    // For top level build we need to remove build tree symlink and install tree
    // symlink as in case of non mutating build it can interfere with the build
    // itself. In case of mutating build they still be ignore then copying sources
    // of to `$cur__target_dir`.
    if (symlinksAreNeeded) {
      await Promise.all([
        unlinkOrRemove(sandboxRootBuildTreeSymlink),
        unlinkOrRemove(sandboxRootInstallTreeSymlink),
      ]);
    }

    let buildSucceeded = false;

    try {
      for (const {command, renderedCommand} of task.buildCommand) {
        spinner.tick(command);
        await driver.executeCommand(command, renderedCommand);
      }

      for (const {command, renderedCommand} of task.installCommand) {
        spinner.tick(command);
        await driver.executeCommand(command, renderedCommand);
      }

      driver.log('rewriting paths in build artefacts');
      spinner.tick('finishing...');
      await rewritePaths(
        config.getInstallPath(task.spec),
        driver.installPath,
        driver.finalInstallPath,
      );

      driver.log('finalizing build');

      // saving esy metadata
      await fs.mkdirp(path.join(driver.installPath, '_esy'));
      await fs.writeFile(
        path.join(driver.installPath, '_esy', 'storePrefix'),
        config.store.path,
      );

      // mv is an atomic op so this is how we implement transactional builds
      await fs.rename(driver.installPath, driver.finalInstallPath);

      buildSucceeded = true;
    } finally {
      if (symlinksAreNeeded) {
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

  await withBuildDriver(task, config, executeBuildCommands);
}

async function initStores(
  store: Store<path.AbsolutePath>,
  localStore: Store<path.AbsolutePath>,
) {
  await Promise.all([
    fs.mkdirp(path.join(store.path, STORE_BUILD_TREE)),
    fs.mkdirp(path.join(store.path, STORE_INSTALL_TREE)),
    fs.mkdirp(path.join(store.path, STORE_STAGE_TREE)),
    fs.mkdirp(path.join(localStore.path, STORE_BUILD_TREE)),
    fs.mkdirp(path.join(localStore.path, STORE_INSTALL_TREE)),
    fs.mkdirp(path.join(localStore.path, STORE_STAGE_TREE)),
  ]);
  if (store.path !== store.prettyPath) {
    fs.symlink(store.path, store.prettyPath);
  }
}

async function renameIfExists(src, dst) {
  try {
    await fs.rmdir(dst);
    await fs.rename(src, dst);
  } catch (err) {
    if (!await fs.exists(src)) {
      return;
    } else {
      throw err;
    }
  }
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

async function importBuild(
  config: Config<path.AbsolutePath>,
  buildPath: path.AbsolutePath,
): Promise<void> {
  const env = {
    ...process.env,
    ESY__SANDBOX: config.sandboxPath,
    ESY__STORE: config.store.path,
  };
  await child.spawn(CURRENT_ESY_EXECUTABLE, ['import-build', buildPath], {env});
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

const dummySpinner = {
  clear() {},
  setPrefix(a, b) {},
  tick(m) {},
  end() {},
};
