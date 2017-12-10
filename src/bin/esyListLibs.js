/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';
import type {BuildSpec, Config} from '../types';

import chalk from 'chalk';
import * as fs from '../lib/fs';
import * as path from '../lib/path';
import {find} from '../graph';
import {spawn} from '../lib/child_process';

import {getSandbox, getBuildConfig} from './esy';
import {Promise} from '../lib/Promise';

export default async function esyLsLibs(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  const sandbox = await getSandbox(ctx);
  const config = await getBuildConfig(ctx);

  const {flags} = invocation.options;

  const ocamlfind = find(sandbox.root, cur => {
    return cur.name === '@opam/ocamlfind';
  });

  if (ocamlfind != null) {
    const ocamlfindCmd = config.getFinalInstallPath(ocamlfind, 'bin', 'ocamlfind');
    const builtIns = await getPackageLibraries(config, ocamlfindCmd);

    console.log(
      await formatBuildSpecTree(config, sandbox.root, {
        indent: 0,
        seen: new Set(),
        isLast: true,
        showAll: !!flags.all,
        ocamlfind: ocamlfindCmd,
        builtIns,
      }),
    );
  } else {
    throw new Error(
      "We couldn't find ocamlfind, consider adding it to your devDependencies",
    );
  }
}

export const options = {
  flags: ['--all'],
};

type FormatBuildSpecTreeCtx = {
  indent: number,
  seen: Set<string>,
  isLast: boolean,
  showAll: boolean,
  ocamlfind: string,
  builtIns: Array<string>,
};

async function formatBuildSpecTree(
  config: Config<*>,
  spec: BuildSpec,
  ctx: FormatBuildSpecTreeCtx,
) {
  const {indent, seen, isLast, showAll} = ctx;
  const dependenciesLines = [];

  const hasSeenIt = seen.has(spec.id);
  if (!hasSeenIt) {
    seen.add(spec.id);
    const dependencies = Array.from(spec.dependencies.values());

    for (const dep of dependencies) {
      const isLast = dep === dependencies[dependencies.length - 1];

      if (showAll || indent < 1) {
        dependenciesLines.push(
          formatBuildSpecTree(config, dep, {...ctx, seen, isLast, indent: indent + 1}),
        );
      }
    }
  } else {
    return '';
  }

  const version = chalk.grey(`@${spec.version}`);
  let name = `${spec.name}${version}`;
  if (indent > 1) {
    name = chalk.grey(name);
  }

  const prefix = indent === 0 ? '' : isLast ? '└── ' : '├── ';
  const info = await formatBuildInfo(config, spec);
  let pkg = `${prefix}${name} ${info}`;
  pkg = pkg.padStart(pkg.length + (indent - 1) * 4, '│   ');

  const libs = (await fs.exists(config.getFinalInstallPath(spec)))
    ? await formatBuildLibrariesList(config, spec, {...ctx, indent: indent + 1})
    : '';

  return [pkg, libs]
    .concat(await Promise.all(dependenciesLines))
    .filter(line => line.length > 0)
    .join('\n');
}

async function formatBuildLibrariesList(
  config: Config<*>,
  spec: BuildSpec,
  ctx: FormatBuildSpecTreeCtx,
) {
  const {indent, ocamlfind, builtIns} = ctx;
  const libraryLines = [];

  const libs = (await getPackageLibraries(config, ocamlfind, spec)).filter(
    lib => builtIns.indexOf(lib) < 0,
  );

  for (const lib of libs) {
    const isLast = lib === libs[libs.length - 1];
    const name = indent > 2 ? chalk.yellow(`${lib}`) : chalk.yellow.bold(`${lib}`);

    const prefix = indent === 0 ? '' : isLast ? '└── ' : '├── ';
    const line = `${prefix}${name}`;

    libraryLines.push(line.padStart(line.length + (indent - 1) * 4, '│   '));
  }

  return libraryLines.join('\n');
}

async function getPackageLibraries(
  config: Config<*>,
  ocamlfind: string,
  spec: ?BuildSpec,
): Promise<Array<string>> {
  const result = await spawn(ocamlfind, ['list'], {
    env: {
      OCAMLPATH: spec != null ? config.getFinalInstallPath(spec, 'lib') : '',
    },
  });

  return result.split('\n').map((line: string) => {
    const [lib, ...version] = line.split(' ');
    return lib;
  });
}

async function formatBuildInfo(config, spec) {
  const buildStatus = (await fs.exists(config.getFinalInstallPath(spec)))
    ? chalk.green('[built]')
    : chalk.blue('[build pending]');
  let info = [buildStatus];
  if (spec.sourceType === 'transient' || spec.sourceType === 'root') {
    info.push(chalk.blue('[local source]'));
  }
  return info.join(' ');
}
