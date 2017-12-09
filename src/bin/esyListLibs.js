/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';
import type {BuildSpec, Config} from '../types';

import chalk from 'chalk';
import { find } from '../graph'
import { spawn } from '../lib/child_process';

import { getSandbox, getBuildConfig } from './esy';
import { Promise } from '../lib/Promise';

export default async function esyListLibs(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  const sandbox = await getSandbox(ctx);
  const config = await getBuildConfig(ctx);

  const { flags } = invocation.options

  const ocamlfind = find(sandbox.root, (cur) => {
    return cur.name === '@opam/ocamlfind'
  });

  if (ocamlfind != null) {
    const ocamlfindCmd = config.getFinalInstallPath(ocamlfind, 'bin', 'ocamlfind')
    const builtIns = await getLibraryPackages(config, ocamlfindCmd)

    console.log(await formatBuildSpecTree(config, sandbox.root, {
      indent: 0,
      seen: new Set(),
      isLast: true,
      showAll: !!flags.all,
      ocamlfind: ocamlfindCmd,
      builtIns
    }));
  } else {
    throw new Error('We couldn\'t find ocamlfind, consider adding it to your devDependencies');
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
  builtIns: Array<string>
};

async function formatBuildSpecTree(
  config: Config<*>,
  spec: BuildSpec,
  ctx: FormatBuildSpecTreeCtx
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
          formatBuildSpecTree(config, dep, {...ctx, seen, indent: indent + 1}),
        );
      }
    }
  } else {
    return ''
  }

  const version = chalk.grey(`@${spec.version}`);
  const name = `${spec.name}${version}`;
  const prefix = indent === 0 ? '' : isLast ? '└── ' : '├── ';
  let line = `${prefix}${name}`;
  line = line.padStart(line.length + (indent - 1) * 4, '│   ');

  const packages = await formatBuildPackagesList(config, spec, ctx)

  return [line, packages]
    .concat(await Promise.all(dependenciesLines))
    .filter(line => line.length > 0)
    .join('\n');
}

async function formatBuildPackagesList(
  config: Config<*>,
  spec: BuildSpec,
  ctx: FormatBuildSpecTreeCtx
) {
  const { indent, ocamlfind, builtIns } = ctx;

  const packages = await getLibraryPackages(config, ocamlfind, spec)

  return packages
    .filter(pkg => builtIns.indexOf(pkg) < 0)
    .map(pkg => {
      let line = `    ${pkg}`;
      line = line.padStart(line.length + (indent - 1) * 4, '    ');
      return line;
    }).join('\n');
}

async function getLibraryPackages(config: Config<*>,
  ocamlfind: string,
  spec: ?BuildSpec
): Promise<Array<string>> {
  const result = await spawn(ocamlfind, ['list'], {
    env: {
      'OCAMLPATH': spec != null ? config.getFinalInstallPath(spec, 'lib') : ''
    }
  })

  return result.split("\n").map((line: string) => {
    const [pkg, ...version] = line.split(" ")
    return pkg
  })
}
