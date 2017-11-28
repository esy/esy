/**
 * @flow
 */

import * as path from 'path';
import {defineTestCaseWithShell} from '../utils';

defineTestCaseWithShell(
  path.join(__dirname, 'fixtures', 'with-dep-with-binary'),
  `
    run esy release dev
    run cd _release/dev

    run npmGlobal pack
    run npmGlobal -g install ./with-dep-with-binary-0.1.0.tgz

    assertStdout say-hello.exe HELLO
  `,
);
