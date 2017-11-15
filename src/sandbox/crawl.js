/**
 * @flow
 */

import type {
  BuildSpec,
  Sandbox,
  BuildEnvironment,
  EnvironmentVarExport,
  PackageManifest,
} from '../types';

import * as JSON5 from 'json5';
import * as path from 'path';
import invariant from 'invariant';
import outdent from 'outdent';

import * as fs from '../lib/fs';
import {computeHash, resolve as resolveNodeModule, normalizePackageName} from '../util';
import * as Env from '../environment';
import * as M from '../package-manifest';

export type Context = {
  manifest: PackageManifest,
  sourcePath: string,

  env: BuildEnvironment,
  sandboxPath: string,
  dependencyTrace: Array<string>,
  crawlBuild: (context: Context) => Promise<BuildSpec>,
  resolveManifest: (dep: Dependency, context: Context) => Promise<?Resolution>,
  options: Options,
};

export type Dependency = {
  type: 'regular' | 'dev' | 'peer',
  pattern: string,
  name: string,
  spec: string,
};

export type Resolution = {
  manifest: PackageManifest,
  sourcePath: string,
};

export type Options = {
  forRelease?: boolean,
};

export async function crawlDependencies<R>(
  dependencySpecs: Dependency[],
  context: Context,
): Promise<{dependencies: Map<string, BuildSpec>, errors: Array<{message: string}>}> {
  const dependencies = new Map();
  const errors = [];
  const missingPackages = [];

  for (const spec of dependencySpecs) {
    if (context.dependencyTrace.indexOf(spec.name) > -1) {
      errors.push({
        message: formatCircularDependenciesError(spec.name, context),
      });
      continue;
    }

    const resolution = await context.resolveManifest(spec, context);
    if (resolution == null) {
      missingPackages.push(spec.name);
      continue;
    }

    const build = await context.crawlBuild({
      ...context,
      manifest: resolution.manifest,
      sourcePath: resolution.sourcePath,
    });

    errors.push(...build.errors);
    dependencies.set(build.id, build);
  }

  if (missingPackages.length > 0) {
    errors.push({
      message: formatMissingPackagesError(missingPackages, context),
    });
  }

  return {dependencies, errors};
}

export async function crawlBuild<R>(context: Context): Promise<BuildSpec> {
  const dependenciesReqs: Dependency[] = [];
  const dependenciesSeen = new Set();
  for (const dep of dependenciesFromObj('regular', context.manifest.dependencies)) {
    if (dependenciesSeen.has(dep.pattern)) {
      continue;
    }
    dependenciesSeen.add(dep.pattern);
    dependenciesReqs.push(dep);
  }
  for (const dep of dependenciesFromObj('peer', context.manifest.peerDependencies)) {
    if (dependenciesSeen.has(dep.pattern)) {
      continue;
    }
    dependenciesSeen.add(dep.pattern);
    dependenciesReqs.push(dep);
  }

  const {dependencies, errors} = await crawlDependencies(dependenciesReqs, {
    ...context,
    dependencyTrace: context.dependencyTrace.concat(context.manifest.name),
  });

  const nextErrors = [...errors];

  const isInstalled = context.manifest._resolved != null;

  const isRoot = context.sandboxPath === context.sourcePath;

  const sourceType = isRoot ? 'root' : !isInstalled ? 'transient' : 'immutable';
  const buildType =
    context.manifest.esy.buildsInSource === '_build'
      ? '_build'
      : Boolean(context.manifest.esy.buildsInSource) ? 'in-source' : 'out-of-source';

  const realSourcePath = await fs.realpath(context.sourcePath);
  const sourcePath = context.sourcePath.startsWith(context.sandboxPath)
    ? path.relative(context.sandboxPath, context.sourcePath)
    : realSourcePath;

  const source = context.manifest._resolved || `local:${realSourcePath}`;
  const id = calculateBuildId(context.env, context.manifest, source, dependencies);

  const spec: BuildSpec = {
    id,
    name: context.manifest.name,
    version: context.manifest.version,
    exportedEnv: context.manifest.esy.exportedEnv,
    buildCommand: context.manifest.esy.build,
    installCommand: context.manifest.esy.install,
    shouldBePersisted: !(isRoot || !isInstalled) || Boolean(context.options.forRelease),
    sourceType,
    buildType,
    sourcePath,
    manifest: context.manifest,
    dependencies,
    errors: nextErrors,
  };

  return spec;
}

export function getDefaultEnvironment(): BuildEnvironment {
  return Env.fromEntries([
    {
      name: 'PATH',
      value: '$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin',
      exclusive: false,
      builtIn: true,
      exported: true,
    },
    {
      name: 'SHELL',
      value: 'env -i /bin/bash --norc --noprofile',
      exclusive: false,
      builtIn: true,
      exported: true,
    },
  ]);
}

function calculateBuildId(
  env: BuildEnvironment,
  manifest: PackageManifest,
  source: string,
  dependencies: Map<string, BuildSpec>,
): string {
  const {name, version, esy} = manifest;
  const h = hash({
    env,
    source,
    manifest: {
      name,
      version,
      esy,
    },
    dependencies: Array.from(dependencies.values(), dep => dep.id),
  });
  if (process.env.NODE_ENV === 'test') {
    return `${normalizePackageName(name)}-${version || '0.0.0'}`;
  } else {
    return `${normalizePackageName(name)}-${version || '0.0.0'}-${h.slice(0, 8)}`;
  }
}

function hash(value: mixed) {
  if (typeof value === 'object') {
    if (value === null) {
      return hash('null');
    } else if (!Array.isArray(value)) {
      const v = value;
      const keys = Object.keys(v);
      keys.sort();
      return hash(keys.map(k => [k, v[k]]));
    } else {
      return hash(JSON.stringify(value.map(hash)));
    }
  } else if (value === undefined) {
    return hash('undefined');
  } else {
    return computeHash(JSON.stringify(value));
  }
}

export function parseDependencyPattern(pattern: string): {name: string, spec: string} {
  if (pattern.startsWith('@')) {
    const [_, name, spec] = pattern.split('@', 3);
    return {name: '@' + name, spec};
  } else {
    const [name, spec] = pattern.split('@');
    return {name, spec};
  }
}

function formatCircularDependenciesError(dependency, context) {
  return outdent`
    Circular dependency "${dependency}" found
      At ${context.dependencyTrace.join(' -> ')}
  `;
}

function formatMissingPackagesError(missingPackages, context) {
  const packagesToReport = missingPackages.slice(0, 3);
  const packagesMessage = packagesToReport.map(p => `"${p}"`).join(', ');
  const extraPackagesMessage =
    missingPackages.length > packagesToReport.length
      ? ` (and ${missingPackages.length - packagesToReport.length} more)`
      : '';
  return outdent`
    Cannot resolve ${packagesMessage}${extraPackagesMessage} packages
      At ${context.dependencyTrace.join(' -> ')}
      Did you forget to run "esy install" command?
  `;
}

export function dependenciesFromObj(
  type: 'regular' | 'peer' | 'dev',
  obj: {[name: string]: string},
): Dependency[] {
  const reqs = [];
  for (const name in obj) {
    const spec = obj[name];
    reqs.push({
      type,
      name,
      spec,
      pattern: `${name}@${spec}`,
    });
  }
  return reqs;
}
