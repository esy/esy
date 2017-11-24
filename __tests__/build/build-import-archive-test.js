/**
 * @flow
 */

import {defineTestCaseWithShell} from './utils';

defineTestCaseWithShell(
  'import-archive',
  `
    run esy build
    run esy export-dependencies
    run ls _export

    # drop global store
    rm -rf ../esy

    DEBUG='esy:*' run esy build
  `,
);
