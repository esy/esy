/**
 * @flow
 */

import * as path from 'path';
import {defineTestCaseWithShell} from '../utils';

defineTestCaseWithShell(
  path.join(__dirname, 'fixtures', 'minimal'),
  `
    run esy release bin
    run cd _release/bin-*
    run npmGlobal pack
    run npmGlobal install ./minimal-0.1.0.tgz

  `,
);
