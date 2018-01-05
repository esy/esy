/**
 * @flow
 */

import type {BuildTask, Store, Config} from './types';

import invariant from 'invariant';
import createLogger from 'debug';
import * as os from 'os';
import * as nodefs from 'fs';
import jsonStableStringify from 'json-stable-stringify';

import * as Stream from './lib/Stream.js';
import * as C from './config.js';
import {PromiseQueue} from './lib/Promise';
import * as path from './lib/path';
import * as fs from './lib/fs';
import * as child from './lib/child_process';
import {fixupErrorSubclassing} from './lib/lang';
import * as Graph from './lib/graph';

import * as T from './build-task.js';
import * as S from './store.js';
import {
  BUILD_TREE_SYMLINK,
  INSTALL_TREE_SYMLINK,
  CURRENT_ESY_EXECUTABLE,
} from './constants';

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

type BuildManager = {
  build(task: BuildTask, force?: boolean): Promise<FinalBuildState>,
  end(): void,
};

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
  buildManager: BuildManager,
  rootTask: BuildTask,
  config: Config<path.AbsolutePath>,
) => {
  await Promise.all([S.initStore(config.store), S.initStore(config.localStore)]);
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
        return buildManager.build(task, true);
      } else {
        return buildManager.build(task);
      }
    },
  );

  return state;
};

/**
 * Build all the sandbox but not the `rootTask`.
 */
export const buildDependencies = async (
  buildManager: BuildManager,
  rootTask: BuildTask,
  config: Config<path.AbsolutePath>,
) => {
  await Promise.all([S.initStore(config.store), S.initStore(config.localStore)]);
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
          return buildManager.build(task, true);
        } else {
          return buildManager.build(task);
        }
      }
    },
  );

  return state;
};

export const createBuildManager = (config: Config<path.AbsolutePath>) => {
  const activitySet = config.reporter.activitySet('-', config.buildConcurrency);
  const buildQueue = new PromiseQueue({concurrency: config.buildConcurrency});
  const taskInProgress = new Map();

  function checkIfIsInStore(spec) {
    return fs.exists(config.getFinalInstallPath(spec));
  }

  async function performBuildOrImport(task, log, spinner): Promise<void> {
    for (const importPath of config.importPaths) {
      for (const basename of [task.spec.id, `${task.spec.id}.tar.gz`]) {
        const buildPath = path.join(importPath, basename);
        const relativeBuildPath = path.relative(config.sandboxPath, buildPath);
        log(`testing for import: ${relativeBuildPath}`);
        if (await fs.exists(buildPath)) {
          log(`importing build: ${relativeBuildPath}`);
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
      log('start building');
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
        freeSpinner(spinner);
        log('build failure');
        return state;
      }
      const endTime = Date.now();
      const timeEllapsed = endTime - startTime;
      const state = {state: 'success', timeEllapsed, cached: false, forced};
      freeSpinner(spinner);
      log('build success');
      return state;
    });
  }

  function performBuildMemoized(
    task: BuildTask,
    forced: boolean = false,
  ): Promise<FinalBuildState> {
    const log = createLogger(`esy:build:${task.spec.name}@${task.spec.version}`);
    const {spec} = task;
    let inProgress = taskInProgress.get(task.id);
    if (inProgress == null) {
      inProgress = Promise.resolve().then(async () => {
        // if build task is forced (for example by one of the deps updated)
        if (forced) {
          return performBuildWithStatusReport(task, log, true);
        } else {
          const isInStore = await checkIfIsInStore(spec);
          if (spec.sourceType === 'immutable' && isInStore) {
            return BUILD_STATE_CACHED_SUCCESS;
          } else if (spec.sourceType !== 'immutable') {
            return performBuildWithStatusReport(task, log, true);
          } else {
            return performBuildWithStatusReport(task, log);
          }
        }
      });
      taskInProgress.set(task.id, inProgress);
    }
    return inProgress;
  }

  return {
    build: performBuildMemoized,
    end() {
      activitySet.end();
    },
  };
};

async function performBuild(
  task: BuildTask,
  config: Config<path.AbsolutePath>,
  spinner,
): Promise<void> {
  const logFilename = `${config.getBuildPath(task.spec)}.log`;
  const logStream = nodefs.createWriteStream(logFilename);

  const isRoot = task.spec.packagePath === '';
  const sandboxRootBuildTreeSymlink = path.join(config.sandboxPath, BUILD_TREE_SYMLINK);
  const sandboxRootInstallTreeSymlink = path.join(
    config.sandboxPath,
    INSTALL_TREE_SYMLINK,
  );
  const symlinksAreNeeded = isRoot && task.spec.buildType !== '_build';

  if (symlinksAreNeeded) {
    await Promise.all([
      unlinkOrRemove(sandboxRootBuildTreeSymlink),
      unlinkOrRemove(sandboxRootInstallTreeSymlink),
    ]);
  }

  let buildSucceeded = false;

  const stdio = ['pipe', 'pipe', 'pipe'];
  const onData = data => {
    config.reporter.info(data);
    logStream.write(data);
  };
  const onProcess = (p, updateStdout, reject, done) => {
    const taskExport = T.exportBuildTask(config, task);
    p.stdin.end(jsonStableStringify(taskExport, {space: '  '}));
    if (p.stderr) {
      p.stderr.on('data', updateStdout);
    }
    if (p.stdout) {
      p.stdout.on('data', updateStdout);
    }
    done();
  };
  try {
    await child.spawn(C.OCAMLRUN_COMMAND, [C.ESY_BUILD_PACKAGE_COMMAND, '-B', '-'], {
      stdio,
      process: onProcess,
    });
    buildSucceeded = true;
  } finally {
    const buildPath = config.getBuildPath(task.spec);
    const installPath = config.getFinalInstallPath(task.spec);
    if (symlinksAreNeeded) {
      // Those can be either created by esy or by previous build process so we
      // forcefully remove them.
      await Promise.all([
        unlinkOrRemove(sandboxRootBuildTreeSymlink),
        unlinkOrRemove(sandboxRootInstallTreeSymlink),
      ]);
      await Promise.all([
        fs.symlink(buildPath, sandboxRootBuildTreeSymlink),
        buildSucceeded && fs.symlink(installPath, sandboxRootInstallTreeSymlink),
      ]);
    }
  }
  await Stream.endWritableStream(logStream);
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
