/**
 * @flow
 */

import type {CommandContext} from './esy';

import outdent from 'outdent';

export default function configCommand(ctx: CommandContext) {
  let [action, configKey] = ctx.args;

  if (action == null) {
    action = 'ls';
  }

  const configSpecs = {
    'store-path': {
      get: () => ctx.config.storePath,
    },
    'sandbox-path': {
      get: () => ctx.config.sandboxPath,
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
