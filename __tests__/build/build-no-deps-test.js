/**
 * @flow
 */

import * as path from 'path';
import {defineTestCaseWithShell} from '../utils';

defineTestCaseWithShell(
  path.join(__dirname, 'fixtures', 'no-deps'),
  `
    run esy build
    assertStdout "esy x no-deps" "no-deps"
  `,
  {snapshotExecutionTrace: true},
);
