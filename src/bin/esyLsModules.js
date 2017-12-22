/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';
import type {BuildSpec, Config} from '../types';
import type {FormatBuildSpecTreeCtx, FormatBuildSpecQueueItem} from '../cli-utils';

import chalk from 'chalk';
import * as fs from '../lib/fs';
import * as path from '../lib/path';
import {find} from '../graph';
import {spawn} from '../lib/child_process';
import {
  getBuildSpecPackages,
  getPackageLibraries,
  formatPackageInfo,
  formatTreeLine,
} from '../cli-utils';

import {getSandbox, getBuildConfig} from './esy';
import {Promise} from '../lib/Promise';

export default async function esyLsLibs(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  const sandbox = await getSandbox(ctx);
  const config = await getBuildConfig(ctx);

  const ocamlfind = find(sandbox.root, cur => {
    return cur.name === '@opam/ocamlfind';
  });

  const ocaml = find(sandbox.root, cur => {
    return cur.name === 'ocaml';
  });

  if (ocamlfind == null) {
    throw new Error(
      "We couldn't find ocamlfind, consider adding it to your devDependencies",
    );
  }

  if (ocaml == null) {
    throw new Error("We couldn't find ocaml, consider adding it to your devDependencies");
  }

  const ocamlfindCmd = config.getFinalInstallPath(ocamlfind, 'bin', 'ocamlfind');
  const ocamlobjinfoCmd = config.getFinalInstallPath(ocaml, 'bin', 'ocamlobjinfo');

  const builtIns = await getPackageLibraries(config, ocamlfindCmd);

  const queue = getBuildSpecPackages(config, sandbox.root, false, false);

  console.log(
    await formatBuildSpecTree(config, queue, {
      ocamlfind: ocamlfindCmd,
      ocamlobjinfo: ocamlobjinfoCmd,
      builtIns,
      lsLibs: invocation.args,
    }),
  );
}

type FormatBuildSpecOptions = {
  ocamlfind: string,
  ocamlobjinfo: string,
  builtIns: Array<string>,
  lsLibs: Array<string>,
};

type PackageMetaInfo = {
  package: string,
  description: string,
  version: string,
  archive: string,
  linkopts: string,
  location: string,
};

async function formatBuildSpecTree(
  config: Config<*>,
  queue: Array<FormatBuildSpecQueueItem>,
  options: FormatBuildSpecOptions,
) {
  const lines = [];

  for (const cur of queue) {
    const {spec, ctx} = cur;

    const pkg = formatPackageInfo(config, spec, {...ctx, isSeen: ctx.level > 1});
    const libs = (await fs.exists(config.getFinalInstallPath(spec)))
      ? formatBuildLibrariesList(config, spec, options, {
          ...ctx,
          level: ctx.level + 1,
        })
      : Promise.resolve('');

    lines.push(
      Promise.all([pkg, libs]).then(([p, l]) => {
        if (ctx.level === 0) {
          return p;
        }
        return l.length ? `${p}\n${l}` : '';
      }),
    );
  }

  const tree = await Promise.all(lines);
  return tree.filter(line => line.length > 0).join('\n');
}

async function formatBuildLibrariesList(
  config: Config<*>,
  spec: BuildSpec,
  options: FormatBuildSpecOptions,
  ctx: FormatBuildSpecTreeCtx,
) {
  const {level} = ctx;
  const {ocamlfind, builtIns, lsLibs} = options;
  const libraryLines = [];

  const libs = (await getPackageLibraries(config, ocamlfind, spec))
    .filter(lib => builtIns.indexOf(lib) < 0)
    .filter(lib => {
      return lsLibs.length ? lsLibs.indexOf(lib) !== -1 : true;
    });

  for (const lib of libs) {
    const isLast = lib === libs[libs.length - 1];

    const name = level > 2 ? chalk.yellow(`${lib}`) : chalk.yellow.bold(`${lib}`);
    const line = formatTreeLine(name, level, isLast);

    libraryLines.push(Promise.resolve(line));

    libraryLines.push(
      formatBuildModulesList(config, spec, lib, options, {...ctx, level: level + 1}),
    );
  }

  const tree = await Promise.all(libraryLines);
  return tree.filter(line => line.length > 0).join('\n');
}

async function formatBuildModulesList(
  config: Config<*>,
  spec: BuildSpec,
  lib: string,
  options: FormatBuildSpecOptions,
  ctx: FormatBuildSpecTreeCtx,
) {
  const {level} = ctx;
  const {ocamlfind, ocamlobjinfo} = options;

  const moduleLines = [];

  const meta = await queryLibraryMeta(config, ocamlfind, spec, lib);

  if (meta.archive === null) {
    const description = chalk.dim(`${meta.description}`);
    return formatTreeLine(description, level, false, false);
  }

  const archive = path.join(meta.location, meta.archive);

  if (false === (await fs.exists(archive))) {
    return '';
  }

  const modules = await queryLibraryModules(config, ocamlobjinfo, archive);

  for (module of modules) {
    const isLast = module === modules[modules.length - 1];
    const name = chalk.cyan(`${module}`);

    const line = formatTreeLine(name, level, isLast);
    moduleLines.push(line);
  }

  return moduleLines.join('\n');
}

async function queryLibraryModules(
  config: Config<*>,
  ocamlobjinfo: string,
  archive: string,
): Promise<Array<string>> {
  const result = await spawn(ocamlobjinfo, [archive]);

  const modules = result
    .split('\n')
    .filter(line => {
      return line.startsWith('Name: ') || line.startsWith('Unit name: ');
    })
    .map(line => {
      const [prefix, module] = line.split(/:\s+/);
      return module
        .split('__')
        .filter(m => !!m)
        .join('.');
    });

  return [...new Set(modules)];
}

async function queryLibraryMeta(
  config: Config<*>,
  ocamlfind: string,
  spec: BuildSpec,
  lib: string,
): Promise<PackageMetaInfo> {
  const result = await spawn(
    ocamlfind,
    ['query', '-predicates', 'byte,native', '-long-format', lib],
    {
      env: {
        OCAMLPATH: config.getFinalInstallPath(spec, 'lib'),
      },
    },
  );

  const lines = result.split('\n').map(line => {
    const [prefix, suffix] = line.split(/:\s+/);
    const key = prefix === 'archive(s)' ? 'archive' : prefix;
    const value = suffix.length ? suffix : null;

    return {[key]: value};
  });

  return Object.assign(...lines);
}
