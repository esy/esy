/**
 * @flow
 */

import type {CommandContext} from './esy';

import * as EsyOpam from '@esy-ocaml/esy-opam';
import * as semver from 'semver';

import * as fs from '../lib/fs';

const AVAILABLE_OCAML_COMPILERS = [['4.4.2000', '~4.4.2000'], ['4.2.3000', '~4.2.3000']];

export default async function importOpamCommand(ctx: CommandContext) {
  const [packageName, packageVersion, opamFilename] = ctx.args;
  if (opamFilename == null) {
    ctx.error(`usage: esy import-opam PACKAGENAME PACKAGEVERSION OPAMFILENAME`);
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
