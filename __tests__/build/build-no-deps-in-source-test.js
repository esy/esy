/**
 * @flow
 */

import * as path from 'path';
import {defineTestCaseWithShell} from '../utils';

defineTestCaseWithShell(
  path.join(__dirname, 'fixtures', 'no-deps-in-source'),
  `
    run esy build
    assertStdout "esy x no-deps-in-source" "no-deps-in-source"
  `,
);
