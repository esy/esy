/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';
import type {PackageManifest} from '../types';

import outdent from 'outdent';

import {buildRelease} from '../release';
import * as M from '../package-manifest';

const currentEsyVersion = require('../../package.json').version;

const AVAILABLE_RELEASE_TYPE = ['dev', 'pack', 'bin'];

export default async function releaseCommand(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  const [type, ...args] = invocation.args;

  if (type == null) {
    ctx.error(outdent`
      Provide release type as argument (dev, pack or bin), examples:

          esy release dev
          esy release pack
          esy release bin

    `);
  }
  if (AVAILABLE_RELEASE_TYPE.indexOf(type) === -1) {
    ctx.error(outdent`
      Invalid release type '${type}', must be one of dev, pack or bin, examples:

          esy release dev
          esy release pack
          esy release bin

    `);
  }
  const {manifest} = await M.read(ctx.sandboxPath);
  await buildRelease({
    type: (type: any),
    version: manifest.version,
    sandboxPath: ctx.sandboxPath,
    esyVersionForDevRelease:
      invocation.options.options.esyVersionForDevRelease || currentEsyVersion,
  });
}

export const options = {
  options: ['--esy-version-for-dev-release'],
};
