/**
 * @flow
 */

import * as path from 'path';
import {defineTestCaseWithShell} from '../utils';

defineTestCaseWithShell(
  path.join(__dirname, 'fixtures', 'import-archive'),
  `
    run esy build
    run esy export-dependencies
    run ls _export

    run rm -rf ../esy

    run esy build
  `,
  {snapshotExecutionTrace: true},
);
