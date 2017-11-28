/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';

import {getSandbox, getBuildConfig} from './esy';
import * as Task from '../build-task';
import * as Sandbox from '../sandbox';
import * as Env from '../environment';
import * as Graph from '../graph.js';
import * as Child from '../lib/child_process.js';
import * as fs from '../lib/fs.js';
import * as path from '../lib/path.js';
import {PromiseQueue} from '../lib/Promise.js';
import * as constants from '../constants.js';

export default async function esyImportDependencies(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  const sandbox = await getSandbox(ctx);
  const config = await getBuildConfig(ctx);
  const [importPath = path.join(config.sandboxPath, '_export')] = invocation.args;

  ctx.reporter.info(`import path set to: ${importPath}`);

  const toImport = [];
  Graph.traverse(sandbox.root, build => {
    switch (build.sourceType) {
      case 'immutable':
        toImport.push(build);
        break;
      case 'transient':
        ctx.reporter.warn(
          `${build.packagePath} is a linked dependency, skipping it for import...`,
        );
        break;
      case 'root':
        // do nothing
        break;
    }
  });

  const importQueue = new PromiseQueue({concurrency: config.buildConcurrency});

  async function importBuild(buildPath) {
    await Child.spawn(constants.CURRENT_ESY_EXECUTABLE, ['import-build', buildPath], {
      stdio: 'inherit',
    });
  }

  function importBuildPaths(build) {
    return [path.join(importPath, build.id), path.join(importPath, `${build.id}.tar.gz`)];
  }

  await Promise.all(
    toImport.map(build =>
      importQueue.add(async () => {
        for (const p of importBuildPaths(build)) {
          if (await fs.exists(p)) {
            await importBuild(p);
            return;
          }
        }
        ctx.reporter.info(`no prebuild artefact found for ${build.id}, skipping...`);
      }),
    ),
  );
}
