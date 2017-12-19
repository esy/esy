/**
 * @flow
 */

import * as path from 'path';
import {defineTestCaseWithShell} from '../utils';

defineTestCaseWithShell(
  path.join(__dirname, 'fixtures', 'custom-prefix'),
  `
    unset ESY__PREFIX
    run esy build
    assertStdout "esy x custom-prefix" "custom-prefix"
  `,
  {snapshotExecutionTrace: true},
);
