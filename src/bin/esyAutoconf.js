/**
 * @flow
 */

import type {CommandContext} from './esy';
import outdent from 'outdent';
import {version} from '../../package.json';

import * as constants from '../constants.js';

export default async function esyAutoconf(ctx: CommandContext) {
  console.log(outdent`
    export ESY__STORE_PADDING_LENGTH="${constants.ESY_STORE_PADDING_LENGTH}"
    export ESY__VERSION="${version}"
  `);
}

export const noHeader = true;
