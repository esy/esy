/**
 * @flow
 */

jest.setTimeout(200000);

import * as path from 'path';
import {defineTestCaseWithShell} from '../utils';

defineTestCaseWithShell(
  path.join(__dirname, 'fixtures', 'with-binary'),
  `
    run esy release dev
    run cd _release/dev
    run npmGlobal pack
    run npmGlobal -g install ./with-binary-0.1.0.tgz
    run say-hello.exe
  `,
);
