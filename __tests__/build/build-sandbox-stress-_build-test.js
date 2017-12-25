/**
 * @flow
 */

import * as path from 'path';
import {defineTestCaseWithShell} from '../utils';

defineTestCaseWithShell(
  path.join(__dirname, 'fixtures', 'sandbox-stress-_build'),
  `
    run esy build
    run esy x echo ok
  `,
  {snapshotExecutionTrace: true},
);
