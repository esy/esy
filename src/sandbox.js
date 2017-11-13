/**
 * @flow
 */

import type {Config, Sandbox, BuildTask, BuildSpec, EnvironmentVar} from './types';
import semver from 'semver';
import * as EsyOpam from '@esy-ocaml/esy-opam';
import * as Task from './build-task';
import {
  type SandboxCrawlContext,
  getDefaultEnvironment,
  crawlDependencies,
  crawlBuild,
  parseDependencyPattern,
} from './build-sandbox';

/**
 * Command env is used to execute arbitrary commands within the sandbox
 * environment.
 *
 * Mainly used for dev, for example you'd want Merlin to be run
 * within this environment.
 */
export function getCommandEnv(
  sandbox: Sandbox,
  config: Config<*>,
): Map<string, EnvironmentVar> {
  const task = Task.fromSandbox(sandbox, config, {
    includeDevDependencies: true,
  });
  const env = new Map(task.env);
  // we are not interested in overriden $SHELL here as user might have its own
  // customizations in .profile or shell's .rc files.
  env.delete('SHELL');
  return env;
}

/**
 * Sandbox env represent the environment which includes the root package.
 *
 * Mainly used to test the package as it's like it being installed.
 */
export function getSandboxEnv(
  sandbox: Sandbox,
  config: Config<*>,
): Map<string, EnvironmentVar> {
  const spec: BuildSpec = {
    id: '__sandbox__',
    name: '__sandbox__',
    version: '0.0.0',
    buildCommand: [],
    installCommand: [],
    exportedEnv: {},
    sourcePath: '',
    sourceType: 'root',
    buildType: 'out-of-source',
    shouldBePersisted: false,
    dependencies: new Map([[sandbox.root.name, sandbox.root]]),
    errors: sandbox.root.errors,
  };
  const {env} = Task.fromBuildSpec(spec, config);
  env.delete('SHELL');
  return env;
}

import * as fs from './lib/fs';
import * as path from './lib/path';
import invariant from 'invariant';
import {LOCKFILE_FILENAME} from '@esy-ocaml/esy-install/src/constants';
import PackageResolver from '@esy-ocaml/esy-install/src/package-resolver';
import Lockfile from '@esy-ocaml/esy-install/src/lockfile';
import {stringify as lockStringify} from '@esy-ocaml/esy-install/src/lockfile';
import YarnConfig from '@esy-ocaml/esy-install/src/config';
import * as fetcher from '@esy-ocaml/esy-install/src/package-fetcher';
import type {Manifest} from '@esy-ocaml/esy-install/src/types';

type SandboxRequest = {
  packageSet: Array<string>,
};

export async function resolveRequestToLockfile(
  config: Config<*>,
  req: SandboxRequest,
): Promise<Lockfile> {
  return (1: any);
}

async function createResolver(config, sandboxPath, requests: Array<string>) {
  const yarnRequests = requests.map(pattern => ({
    pattern,
    registry: 'npm',
    optional: false,
  }));

  const lockfile = await Lockfile.fromDirectory(sandboxPath);

  const yarnConfig = new YarnConfig(config.reporter);
  await yarnConfig.init();

  const packageResolver = new PackageResolver(yarnConfig, lockfile);
  await packageResolver.init(yarnRequests);

  // write lockfile
  const lockfileObject = lockfile.getLockfile(packageResolver.patterns);
  const lockfileFilename = path.join(sandboxPath, LOCKFILE_FILENAME);
  const lockSource = lockStringify(lockfileObject, false, true);
  await fs.writeFile(lockfileFilename, lockSource);

  lockfile.cache = lockfileObject;

  const manifests: Array<Manifest> = await fetcher.fetch(
    packageResolver.getManifests(),
    yarnConfig,
  );

  const manifestLocByResolution: Map<string, Manifest> = new Map();
  const manifestByName: Map<string, Map<string, Manifest>> = new Map();

  for (const manifest of manifests) {
    if (manifest._remote != null && manifest._remote.resolved != null) {
      manifestLocByResolution.set(manifest._remote.resolved, manifest);
      const manifestByVersion = manifestByName.get(manifest.name);
      if (manifestByVersion == null) {
        manifestByName.set(manifest.name, new Map([[manifest.version, manifest]]));
      } else {
        manifestByVersion.set(manifest.version, manifest);
      }
    }
  }

  const resolver = async dep => {
    if (dep.type === 'peer') {
      // peer dep resolutions aren't stored in a lockfile so we resolve them
      // against installed packages here
      const versionMap = manifestByName.get(dep.name);
      if (versionMap == null) {
        return null;
      }
      const versions = Array.from(versionMap.keys());
      versions.sort((a, b) => -1 * EsyOpam.versionCompare(a, b));
      for (const v of versions) {
        if (semver.satisfies(v, dep.spec)) {
          const manifest = versionMap.get(v);
          if (manifest != null && manifest._loc != null) {
            return manifest._loc;
          }
        }
      }
      return null;
    } else {
      const lockedManifest = lockfile.getLocked(dep.pattern);
      if (lockedManifest == null || lockedManifest.resolved == null) {
        return null;
      }
      const manifest = manifestLocByResolution.get(lockedManifest.resolved);
      if (manifest == null || manifest._loc == null) {
        return null;
      }
      return manifest._loc;
    }
  };

  return resolver;
}

export async function fromRequest(
  request: Array<string>,
  config: Config<*>,
): Promise<Sandbox> {
  const sandboxPath = config.getSandboxPath(request);
  await fs.mkdirp(sandboxPath);
  const resolve = await createResolver(config, sandboxPath, request);
  const env = getDefaultEnvironment();

  const resolutionCache: Map<string, Promise<string>> = new Map();

  async function resolveOrFail(spec) {
    const resolution = await resolve(spec);
    // TODO: proper error here
    invariant(resolution != null, 'Unable to resolve: %s', spec.pattern);
    return resolution;
  }

  function resolveCached(spec, baseDir): Promise<string> {
    let resolution = resolutionCache.get(spec.pattern);
    if (resolution == null) {
      resolution = resolveOrFail(spec);
      resolutionCache.set(spec.pattern, resolution);
    }
    return resolution;
  }

  const buildCache: Map<string, Promise<BuildSpec>> = new Map();
  function crawlBuildCached(sourcePath, context): Promise<BuildSpec> {
    let build = buildCache.get(sourcePath);
    if (build == null) {
      build = crawlBuild(sourcePath, context);
      buildCache.set(sourcePath, build);
    }
    return build;
  }

  const crawlContext: SandboxCrawlContext = {
    env: getDefaultEnvironment(),
    sandboxPath: '/tmp',
    resolve: resolveCached,
    crawlBuild: crawlBuildCached,
    dependencyTrace: [],
    options: {forRelease: true},
  };

  const dependenciesReqs = request.map(pattern => {
    const {name, spec} = parseDependencyPattern(pattern);
    return {type: 'regular', name, spec, pattern};
  });
  const {dependencies} = await crawlDependencies('/tmp', dependenciesReqs, crawlContext);
  const root: BuildSpec = {
    id: '__sandbox__',
    name: '__sandbox__',
    version: '0.0.0',
    buildCommand: [],
    installCommand: [],
    exportedEnv: {},
    sourcePath: '',
    sourceType: 'root',
    buildType: 'out-of-source',
    shouldBePersisted: false,
    dependencies,
    // TODO:
    errors: [],
  };

  return {env, root, devDependencies: new Map()};
}
