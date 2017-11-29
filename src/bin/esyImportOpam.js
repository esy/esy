/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';

import * as EsyOpam from '@esy-ocaml/esy-opam';
import * as semver from 'semver';
import outdent from 'outdent';

import * as fs from '../lib/fs.js';
import * as path from '../lib/path.js';

const AVAILABLE_OCAML_COMPILERS = [['4.4.2000', '~4.4.2000'], ['4.2.3000', '~4.2.3000']];

export default async function importOpamCommand(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  const [packageName, packageVersion, opamFilename] = invocation.args;
  if (opamFilename == null) {
    ctx.error(`usage: esy import-opam <packagename> <packageversion> <opamfilename>`);
  }
  if (!await fs.exists(opamFilename)) {
    const suggestions = await findOpamFiles(path.dirname(opamFilename));
    const error = `File "${opamFilename}" doesn't exist`;
    if (suggestions.length > 0) {
      ctx.error(outdent`
        ${error}, there are other opam files in the directory:
        ${suggestions.map(file => `  "${file}"`).join('\n')}
      `);
    } else {
      ctx.error(error);
    }
  }
  const opamData = await fs.readFile(opamFilename);
  const opam = EsyOpam.parseOpam(opamData);
  const packageJson = EsyOpam.renderOpam(packageName, packageVersion, opam);
  // We inject "ocaml" into devDependencies as this is something which is have
  // to be done usually.
  packageJson.peerDependencies = packageJson.peerDependencies || {};
  packageJson.devDependencies = packageJson.devDependencies || {};
  const ocamlReq = packageJson.peerDependencies.ocaml || 'x.x.x';
  for (const [version, resolution] of AVAILABLE_OCAML_COMPILERS) {
    if (semver.satisfies(version, ocamlReq)) {
      packageJson.devDependencies.ocaml = resolution;
      break;
    }
  }
  // We don't need this as only opam-fetcher from esy-install can apply them. We
  // expect developers to apply needed patches before releasing converted
  // package on github or elsewhere.
  // $FlowFixMe: suppress therefore...
  delete packageJson._esy_opam_patches;
  console.log(JSON.stringify(packageJson, null, 2));
}

async function findOpamFiles(dirname) {
  if (!await fs.exists(dirname)) {
    return [];
  }
  const files = await fs.readdir(dirname);
  const opamFiles = files
    .filter(file => file === 'opam' || file.endsWith('.opam'))
    .map(file => path.join(dirname, file));
  return opamFiles;
}

export const noHeader = true;
