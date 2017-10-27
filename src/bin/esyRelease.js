/**
 * @flow
 */

import type {CommandContext} from './esy';

import outdent from 'outdent';

import {buildRelease} from '../release';
import {readManifest} from '../build-sandbox';

const AVAILABLE_RELEASE_TYPE = ['dev', 'pack', 'bin'];

export default async function releaseCommand(ctx: CommandContext) {
  const [type, ...args] = ctx.args;

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
  const pkg = await readManifest(ctx.sandboxPath);
  await buildRelease({
    type: (type: any),
    version: pkg.version,
    sandboxPath: ctx.sandboxPath,
  });
}
