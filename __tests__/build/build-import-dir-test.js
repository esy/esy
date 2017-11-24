/**
 * @flow
 */

import {defineTestCaseWithShell} from './utils';

defineTestCaseWithShell(
  'import-archive',
  `
    run esy build
    run esy export-dependencies
    (cd _export && tar xzf dep-1.0.0.tar.gz && rm dep-1.0.0.tar.gz)
    run ls _export

    # drop global store
    rm -rf ../esy

    DEBUG='esy:*' run esy build
  `,
);
