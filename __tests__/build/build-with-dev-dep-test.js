/**
 * @flow
 */

import * as path from 'path';
import {defineTestCaseWithShell} from '../utils';

defineTestCaseWithShell(
  path.join(__dirname, 'fixtures', 'with-dev-dep'),
  `
    run esy build

    # package "dep" should be visible in all envs
    assertStdout "esy dep" "dep"
    assertStdout "esy b dep" "dep"
    assertStdout "esy x dep" "dep"

    # package "dev-dep" should be visible only in command env
    assertStdout "esy dev-dep" "dev-dep"
    runAndExpectFailure esy b dev-dep
    assertStdout "esy x dev-dep" "dev-dep"

    assertStdout "esy x with-dev-dep" "with-dev-dep"
  `,
);
