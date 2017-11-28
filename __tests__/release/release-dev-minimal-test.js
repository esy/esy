/**
 * @flow
 */

jest.setTimeout(200000);

import * as path from 'path';
import {defineTestCaseWithShell} from '../utils';

defineTestCaseWithShell(
  path.join(__dirname, 'fixtures', 'minimal'),
  `
    run esy release dev
    run cd _release/dev
    ls ./
    ls ./r
  `,
);
