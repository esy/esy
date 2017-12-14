/**
 * @flow
 */

import * as path from 'path';
import {defineTestCaseWithShell} from '../utils';

defineTestCaseWithShell(
  path.join(__dirname, 'fixtures', 'no-deps-_build'),
  `
    run esy build
    run ls
    run ls _build
    run esy x no-deps-_build
    assertStdout "esy x no-deps-_build" "no-deps-_build"
  `,
  {snapshotExecutionTrace: true},
);
