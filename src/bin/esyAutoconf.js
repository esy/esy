/**
 * @flow
 */

import type {CommandContext} from './esy';
import outdent from 'outdent';
import {version} from '../../package.json';

import * as constants from '../constants.js';

export default async function esyAutoconf(ctx: CommandContext) {
  console.log(outdent`
    # Esy version
    export ESY__VERSION="${version}"
    # Esy store format version
    export ESY__STORE_VERSION="${constants.ESY_STORE_VERSION}"
    # Esy metadata format version
    export ESY__METADATA_VERSION="${constants.ESY_METADATA_VERSION}"
    # Store path padding required for relocatable artifacts
    export ESY__STORE_PADDING_LENGTH="${constants.ESY_STORE_PADDING_LENGTH}"
  `);
}

export const noHeader = true;
