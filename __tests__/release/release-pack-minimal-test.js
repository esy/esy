/**
 * @flow
 */

jest.setTimeout(200000);

import * as path from 'path';
import {defineTestCaseWithShell} from '../utils';

defineTestCaseWithShell(
  path.join(__dirname, 'fixtures', 'minimal'),
  `
    run esy release pack
    run cd _release/pack
    run npmGlobal pack
    run npmGlobal install ./minimal-0.1.0.tgz
  `,
);
