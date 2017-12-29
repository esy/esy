/**
 * @flow
 */

import * as path from './lib/path';
import type {Reporter} from '@esy-ocaml/esy-install/src/reporters';

export type {Reporter};

export type StoreTree = 'i' | 'b' | 's';

export type Store<+Path: path.Path> = {
  +path: Path,
  +prettyPath: Path,
  +version: number,

  has(BuildSpec): Promise<boolean>,
  getPath(StoreTree, BuildSpec, ...path: Array<string>): Path,
};

export type EnvironmentBinding = {|
  +name: string,
  +value: string,
  +builtIn: boolean,
  +exclusive: boolean,
  +origin: ?BuildSpec,
|};

export type Environment = Array<EnvironmentBinding>;

export type BuildScope = Map<string, BuildScope | BuildScopeBinding>;

export type BuildScopeBinding = {|
  name: string,
  value: string,
  origin: ?BuildSpec,
|};

export type EnvironmentVarExport = {
  val: string,
  scope?: string,
  exclusive?: boolean,
  __BUILT_IN_DO_NOT_USE_OR_YOU_WILL_BE_PIPd?: boolean,
};

export type SourceType = 'immutable' | 'transient' | 'root';
export type BuildType = 'out-of-source' | '_build' | 'in-source';

/**
 * Describes build.
 */
export type BuildSpec = {|
  /** Unique identifier */
  +id: string,

  /** Unique identifier */
  +idInfo: mixed,

  /** Build name */
  +name: string,

  /** Build version */
  +version: string,

  /** Command which is needed to execute build */
  +buildCommand: Array<Array<string> | string>,

  /** Command which is needed to execute install */
  +installCommand: Array<Array<string> | string>,

  /** Environment exported by built. */
  +exportedEnv: {[name: string]: EnvironmentVarExport},

  /**
   * Path to the package declaration inside `node_modules` directory.
   *
   * Note that it might not be the same as source path.
   */
  +packagePath: string,

  /**
   * Path to the source tree.
   *
   * That's where sources are located but not necessary the location where the
   * build is executed as build process (or some other process) can relocate sources before the build.
   *
   * This can be either an absolute path (for packages outside of the sandbox)
   * or a relative path within the sandbox root.
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
  +sourceType: SourceType,

  /**
   * Build type.
   *
   * 'out-of-source' means it doesn't pollute $cur__root
   * '_build'        means it pollutes only $cur__root/_build inside the $cur__root
   * 'in-source'     means it pollutes in $cur__root
   */
  +buildType: BuildType,

  /**
   * Set of dependencies which must be build/installed before this build can
   * happen
   */
  +dependencies: Map<string, BuildSpec>,

  /**
   * A list of errors found in build definitions.
   */
  +errors: Array<BuildConfigError>,
|};

export type BuildTaskCommand = {
  command: Array<string>,
  renderedCommand: Array<string>,
};

/**
 * A concrete build task with command list and env ready for execution.
 */
export type BuildTask = {
  /**
   * Global unique id of the build.
   */
  +id: string,

  /**
   * List of commands needed to build the package.
   */
  +buildCommand: Array<BuildTaskCommand>,

  /**
   * List of commands needed to install the package.
   */
  +installCommand: Array<BuildTaskCommand>,

  /**
   * Environment for the build.
   */
  +env: Environment,

  /**
   * Scope which was used to eval environment and command strings.
   */
  +scope: BuildScope,

  /**
   * Build dependencies.
   */
  +dependencies: Map<string, BuildTask>,

  /**
   * Spec the build was generated from.
   */
  +spec: BuildSpec,

  /**
   * A list of errors found in build.
   */
  +errors: Array<BuildConfigError>,
};

export type BuildTaskExport = {
  id: string,
  name: string,
  version: string,
  sourceType: SourceType,
  buildType: BuildType,
  build: Array<Array<string>>,
  install: Array<Array<string>>,
  sourcePath: string,
  stagePath: string,
  installPath: string,
  buildPath: string,
  env: {[name: string]: string},
};

export type BuildPlatform = 'darwin' | 'linux' | 'cygwin';

/**
 * Build configuration.
 */
export type Config<+Path: path.Path, RPath: Path = Path> = {|
  reporter: Reporter,

  /**
   * Which platform the build will actually be performed on. Not necessarily
   * the same platform that is constructing the build plan.
   */
  +buildPlatform: BuildPlatform,

  +store: Store<Path>,

  +localStore: Store<Path>,

  +buildConcurrency: number,

  /**
   * List of read only stores from which Esy could import built artifacts as
   * needed.
   */
  +importPaths: Array<path.AbsolutePath>,

  /**
   * Path to a sandbox root.
   * TODO: Model this as sufficiently abstract to prevent treating this as a
   * string containing a file path. It very well might contain the name of an
   * environment variable that eventually will contain the actual path.
   */
  +sandboxPath: Path,

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

  /**
   * Generate a pretty version of the path if possible.
   */
  prettifyPath: (path: string) => string,

  /**
   * Generate path for the sandbox based on package requests.
   */
  getSandboxPath: (requests: Array<string>) => string,
|};

/**
 * A build root together with a global env.
 *
 * Note that usually builds do not exist outside of build sandboxes as their own
 * identities a made dependent on a global env of the sandbox.
 */
export type Sandbox = {
  env: Environment,
  root: BuildSpec,
  devDependencies: Map<string, BuildSpec>,
};

export type SandboxType = 'project' | 'global';

export type PackageManifestDependenciesCollection = {
  [name: string]: string,
};

export type PackageManifest = {
  name: string,
  version: string,

  dependencies: PackageManifestDependenciesCollection,
  peerDependencies: PackageManifestDependenciesCollection,
  devDependencies: PackageManifestDependenciesCollection,
  optDependencies: PackageManifestDependenciesCollection,
  optionalDependencies: PackageManifestDependenciesCollection,

  // This is specific to npm, make sure we get rid of that if we want to port to
  // other package installers.
  //
  // npm puts a resolved name there, for example for packages installed from
  // github — it would be a URL to git repo and a sha1 hash of the tree.
  _resolved?: string,

  _loc?: string,

  esy: EsyPackageManifest,
};

/**
 * This specifies Esy configuration within a package.json.
 *
 * Any change here likely results in minor or major version bump.
 */
export type EsyPackageManifest = {
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

  sandboxType: SandboxType,

  /**
   * Configuration related to the releases produced by `esy release` command.
   */
  release: {
    /**
     * List of executable names to be exposed by the release installation.
     */
    releasedBinaries?: Array<string>,

    /**
     * List of package names to be deleted from the binary releases.
     *
     * This is usually used to exclude build time dependencies. Later when we
     * get support for build time dependencies in Esy we can deprecate this
     * configuration field.
     */
    deleteFromBinaryRelease?: Array<string>,
  },
};

export type CommandSpec = Array<string | Array<string>>;

export type ExportEnvironmentSpec = {[name: string]: EnvironmentVarExport};

export type BuildConfigError = {
  reason: string,
  origin: ?BuildSpec,
};
