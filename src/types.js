/**
 * @flow
 */

import * as path from './lib/path';

export type StoreTree = 'i' | 'b' | 's';

export type Store<+Path: path.Path> = {
  +path: Path,
  has(BuildSpec): Promise<boolean>,
  getPath(StoreTree, BuildSpec, ...path: Array<string>): Path,
};

export type EnvironmentVar = {
  name: string,
  value: string,
  exported: boolean,
  builtIn: boolean,
  exclusive: boolean,
  spec?: BuildSpec,
};

export type BuildEnvironment = Map<string, EnvironmentVar>;

export type EnvironmentVarExport = {
  val: string,
  scope?: string,
  exclusive?: boolean,
  __BUILT_IN_DO_NOT_USE_OR_YOU_WILL_BE_PIPd?: boolean,
};

/**
 * Describes build.
 */
export type BuildSpec = {
  /** Unique identifier */
  +id: string,

  /** Build name */
  +name: string,

  /** Build version */
  +version: string,

  /** Command which is needed to execute build */
  +buildCommand: Array<string | Array<string>>,

  /** Command which is needed to execute install */
  +installCommand: Array<string | Array<string>>,

  /** Environment exported by built. */
  +exportedEnv: {[name: string]: EnvironmentVarExport},

  /**
   * Path tof the source tree relative to sandbox root.
   *
   * That's where sources are located but not necessary the location where the
   * build is executed as build process (or some other process) can relocate sources before the build.
   */
  +sourcePath: string,

  /**
   * Source type.
   *
   * 'immutable' means we can persist build artefacts.
   * 'transient' means sources can be changed between build invokations and we
   *             cannot simply cache artefacts.
   * 'root'      means this is the root project source
   */
  +sourceType: 'immutable' | 'transient' | 'root',

  /**
   * Build type.
   *
   * 'out-of-source' means it doesn't pollute $cur__root
   * '_build'        means it pollutes only $cur__root/_build inside the $cur__root
   * 'in-source'     means it pollutes in $cur__root
   */
  +buildType: 'out-of-source' | '_build' | 'in-source',

  /**
   * If build should be persisted in store.
   *
   * Builds from released versions of packages should be persisted in store as
   * they don't change at all. On the other side builds from dev sources
   * shouldn't be persisted.
   */
  +shouldBePersisted: boolean,

  /**
   * Set of dependencies which must be build/installed before this build can
   * happen
   */
  +dependencies: Map<string, BuildSpec>,

  /**
   * A list of errors found in build definitions.
   */
  +errors: {message: string}[],
};

export type BuildTaskCommand = {
  command: string,
  renderedCommand: string,
};

/**
 * A concrete build task with command list and env ready for execution.
 */
export type BuildTask = {
  +id: string,
  +buildCommand: Array<BuildTaskCommand>,
  +installCommand: Array<BuildTaskCommand>,
  +env: Map<string, EnvironmentVar>,
  +scope: Map<string, EnvironmentVar>,
  +dependencies: Map<string, BuildTask>,
  +spec: BuildSpec,
};

export type BuildPlatform = 'darwin' | 'linux' | 'cygwin';

/**
 * Build configuration.
 */
export type Config<+Path: path.Path, RPath: Path = Path> = {
  /**
   * Which platform the build will actually be performed on. Not necessarily
   * the same platform that is constructing the build plan.
   */
  +buildPlatform: BuildPlatform,

  +store: Store<Path>,

  +localStore: Store<Path>,

  /**
   * List of read only stores from which Esy could import built artifacts as
   * needed.
   */
  +readOnlyStores: Array<Store<path.AbsolutePath>>,

  /**
   * Path to a sandbox root.
   * TODO: Model this as sufficiently abstract to prevent treating this as a
   * string containing a file path. It very well might contain the name of an
   * environment variable that eventually will contain the actual path.
   */
  +sandboxPath: Path,

  /**
   * Check if build requires its root relocated.
   */
  requiresRootRelocation: (build: BuildSpec) => boolean,

  /**
   * Generate path where sources of the builds are located.
   */
  getSourcePath: (build: BuildSpec, ...segments: string[]) => RPath,

  /**
   * Generate path from where the build executes.
   */
  getRootPath: (build: BuildSpec, ...segments: string[]) => RPath,

  /**
   * Generate path where build artefacts should be placed.
   */
  getBuildPath: (build: BuildSpec, ...segments: string[]) => RPath,

  /**
   * Generate path where installation artefacts should be placed.
   */
  getInstallPath: (build: BuildSpec, ...segments: string[]) => RPath,

  /**
   * Generate path where finalized installation artefacts should be placed.
   *
   * Installation and final installation path are different because we want to
   * do atomic installs (possible by buiilding in one location and then mv'ing
   * to another, final location).
   */
  getFinalInstallPath: (build: BuildSpec, ...segments: string[]) => RPath,
};

/**
 * A build root together with a global env.
 *
 * Note that usually builds do not exist outside of build sandboxes as their own
 * identities a made dependent on a global env of the sandbox.
 */
export type BuildSandbox = {
  env: BuildEnvironment,
  root: BuildSpec,
};

/**
 * This specifies Esy configuration within a package.json.
 *
 * Any change here likely results in minor or major version bump.
 */
export type EsySpec = {
  /**
   * Commands to execute during build phase.
   */
  build: CommandSpec,

  /**
   * Commands to execute during install phase.
   */
  install: CommandSpec,

  /**
   * Type of the build.
   */
  buildsInSource: true | false | '_build',

  /**
   * Environment exported by the package
   */
  exportedEnv: ExportEnvironmentSpec,
};

export type CommandSpec = null | string | Array<string | Array<string>>;

export type ExportEnvironmentSpec = {[name: string]: EnvironmentVarExport};
