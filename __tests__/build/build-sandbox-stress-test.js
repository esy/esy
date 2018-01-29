/**
 * @flow
 */

import * as path from 'path';
import {defineTestCaseWithShell} from '../utils';

defineTestCaseWithShell(
  path.join(__dirname, 'fixtures', 'sandbox-stress'),
  `
    run esy build
    run esy x echo ok
  `,
);
