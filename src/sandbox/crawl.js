/**
 * @flow
 */

import type {
  BuildSpec,
  Sandbox,
  BuildEnvironment,
  EnvironmentVarExport,
  PackageManifest,
  Reporter,
} from '../types';

import * as JSON5 from 'json5';
import jsonStableStringify from 'json-stable-stringify';
import * as path from 'path';
import invariant from 'invariant';
import outdent from 'outdent';

import * as fs from '../lib/fs';
import * as crypto from '../lib/crypto';
import {resolve as resolveNodeModule, normalizePackageName} from '../util';
import * as Env from '../environment';
import * as constants from '../constants';
import * as M from '../package-manifest';

export type Context = {
  manifest: PackageManifest,
  packagePath: string,

  env: BuildEnvironment,
  sandboxPath: string,
  dependencyTrace: Array<string>,
  crawlBuild: (context: Context) => Promise<BuildSpec>,
  resolveManifest: (dep: Dependency, context: Context) => Promise<?Resolution>,
  options: Options,
  reporter: Reporter,
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
    context.reporter.verbose(
      `crawl-build-depenedency: ${spec.pattern} at ${context.packagePath}`,
    );
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
      packagePath: resolution.sourcePath,
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
  context.reporter.verbose(`crawl-build: ${context.packagePath}`);
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

  let hasTransientDep = false;
  for (const dep of dependencies.values()) {
    if (dep.sourceType === 'transient') {
      hasTransientDep = true;
      break;
    }
  }

  const isRoot = context.sandboxPath === context.packagePath;

  let sourceType = isRoot
    ? 'root'
    : !isInstalled || hasTransientDep ? 'transient' : 'immutable';

  if (context.options.forRelease) {
    sourceType = 'immutable';
  }

  const buildType =
    context.manifest.esy.buildsInSource === '_build'
      ? '_build'
      : Boolean(context.manifest.esy.buildsInSource) ? 'in-source' : 'out-of-source';

  const linkReference = path.join(context.packagePath, constants.REFERENCE_FILENAME);

  let sourcePath = context.packagePath;
  if (await fs.exists(linkReference)) {
    sourcePath = await fs.readFile(linkReference);
    sourcePath = sourcePath.trim();
  }
  const realSourcePath = await fs.realpath(sourcePath);

  if (realSourcePath.indexOf(context.sandboxPath) === 0) {
    sourcePath = path.relative(context.sandboxPath, realSourcePath);
  } else {
    sourcePath = realSourcePath;
  }

  const {id, info: idInfo} = calculateBuildIdentity(
    context.env,
    context.manifest,
    realSourcePath,
    dependencies,
  );

  const spec: BuildSpec = {
    id,
    idInfo,
    name: context.manifest.name,
    version: context.manifest.version,
    exportedEnv: context.manifest.esy.exportedEnv,
    buildCommand: context.manifest.esy.build,
    installCommand: context.manifest.esy.install,
    sourceType,
    packagePath: path.relative(context.sandboxPath, context.packagePath),
    buildType,
    sourcePath,
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

function calculateBuildIdentity(
  env: BuildEnvironment,
  manifest: PackageManifest,
  sourcePath: string,
  dependencies: Map<string, BuildSpec>,
): {id: string, info: mixed} {
  const source = manifest._resolved || `local:${sourcePath}`;
  const {name, version, esy} = manifest;
  const info = {
    env,
    source,
    manifest: {
      name,
      version,
      esy,
    },
    dependencies: Array.from(dependencies.values(), dep => dep.id),
  };
  const h = crypto.hash(jsonStableStringify(info, {space: '  '}), 'sha1');
  const id =
    process.env.NODE_ENV === 'test'
      ? `${normalizePackageName(name)}-${version || '0.0.0'}`
      : `${normalizePackageName(name)}-${version || '0.0.0'}-${h.slice(0, 8)}`;
  return {id, info};
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
