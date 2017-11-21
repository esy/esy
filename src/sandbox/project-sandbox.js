/**
 * @flow
 */

import type {BuildSpec, Sandbox, Reporter} from '../types';

import * as path from 'path';

import {NoopReporter} from '@esy-ocaml/esy-install/src/reporters';
import * as M from '../package-manifest';
import * as Crawl from './crawl';

export type Options = {
  forRelease?: boolean,
  reporter?: Reporter,
};

/**
 * Create a project sandbox.
 */
export async function create(
  sandboxPath: string,
  options: Options = {},
): Promise<Sandbox> {
  const reporter = options.reporter || new NoopReporter();
  const manifestResolutionCache = new Map();

  function resolveManifestCached(dep, context): Promise<?Crawl.Resolution> {
    const baseDirectory = context.packagePath;
    const key = `${baseDirectory}__${dep.name}`;
    let resolution = manifestResolutionCache.get(key);
    if (resolution == null) {
      resolution = M.resolve(dep.name, baseDirectory).then(res => {
        if (res == null) {
          return res;
        }
        const sourcePath = path.dirname(res.filename);
        reporter.verbose(
          `resolved ${dep.name} at ${context.packagePath} to ${sourcePath}`,
        );
        return {
          manifest: res.manifest,
          sourcePath,
        };
      });
      manifestResolutionCache.set(key, resolution);
    }
    return resolution;
  }

  const buildCache: Map<string, Promise<BuildSpec>> = new Map();

  function crawlBuildCached(context): Promise<BuildSpec> {
    const key = context.packagePath;
    let build = buildCache.get(key);
    if (build == null) {
      build = Crawl.crawlBuild(context);
      buildCache.set(key, build);
    }
    return build;
  }

  const env = Crawl.getDefaultEnvironment();

  const {manifest, filename: manifestFilename} = await M.read(sandboxPath);

  const crawlContext: Crawl.Context = {
    reporter,
    manifest,
    env,
    packagePath: sandboxPath,
    sandboxPath,
    resolveManifest: resolveManifestCached,
    crawlBuild: crawlBuildCached,
    dependencyTrace: [],
    options,
  };

  const root = await crawlBuildCached(crawlContext);

  const devDependenciesReqs = Crawl.dependenciesFromObj('dev', manifest.devDependencies);
  const {dependencies: devDependencies} = await Crawl.crawlDependencies(
    devDependenciesReqs,
    crawlContext,
  );

  return {env, devDependencies, root};
}
