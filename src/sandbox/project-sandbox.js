/**
 * @flow
 */

import type {BuildSpec, Sandbox} from '../types';

import * as path from 'path';

import * as M from '../package-manifest';
import * as Crawl from './crawl';

export type Options = {
  forRelease?: boolean,
};

/**
 * Create a project sandbox.
 */
export async function create(
  sandboxPath: string,
  options: Options = {},
): Promise<Sandbox> {
  const manifestResolutionCache = new Map();

  function resolveManifestCached(dep, context): Promise<?Crawl.Resolution> {
    const baseDirectory = context.sourcePath;
    const key = `${baseDirectory}__${dep.name}`;
    let resolution = manifestResolutionCache.get(key);
    if (resolution == null) {
      resolution = M.resolve(dep.name, baseDirectory).then(res => {
        if (res == null) {
          return res;
        }
        return {
          manifest: res.manifest,
          sourcePath: path.dirname(res.filename),
        };
      });
      manifestResolutionCache.set(key, resolution);
    }
    return resolution;
  }

  const buildCache: Map<string, Promise<BuildSpec>> = new Map();

  function crawlBuildCached(context): Promise<BuildSpec> {
    const key = context.sourcePath;
    let build = buildCache.get(key);
    if (build == null) {
      build = Crawl.crawlBuild(context);
      buildCache.set(key, build);
    }
    return build;
  }

  const env = Crawl.getDefaultEnvironment();

  const {manifest, filename: manifestFilename} = await M.read(sandboxPath);

  const crawlContext: Crawl.SandboxCrawlContext = {
    manifest,
    env,
    sourcePath: sandboxPath,
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
