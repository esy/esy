/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';

import {getBuildConfig} from './esy';
import * as constants from '../constants.js';

import outdent from 'outdent';

export default async function configCommand(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  let [action, configKey] = invocation.args;

  if (action == null) {
    action = 'ls';
  }

  const config = await getBuildConfig(ctx);

  const configSpecs = {
    storePath: {
      get: () => config.store.path,
    },
    sandboxPath: {
      get: () => config.sandboxPath,
    },
    importPaths: {
      get: () => config.importPaths.join(':'),
    },
    storeVersion: {
      get: () => constants.ESY_STORE_VERSION,
    },
    metadataVersion: {
      get: () => constants.ESY_METADATA_VERSION,
    },
  };

  switch (action) {
    case 'get': {
      const configSpec = configSpecs[configKey];
      if (configSpec == null) {
        const configKeySet = Object.keys(configSpecs);
        ctx.error(outdent`
          usage: esy config get CONFIGKEY

            where CONFIGKEY should be one of: ${configKeySet.join(', ')}

        `);
      }
      console.log(configSpec.get());
      break;
    }
    case 'ls':
      for (const configKey of Object.keys(configSpecs)) {
        const configSpec = configSpecs[configKey];
        console.log(`${configKey}: ${configSpec.get()}`);
      }
      break;

    default:
      ctx.error(outdent`
        usage: esy config get|ls
      `);
  }
}
