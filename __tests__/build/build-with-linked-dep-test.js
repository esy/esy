/**
 * @flow
 */

import * as path from 'path';
import {defineTestCaseWithShell} from '../utils';

defineTestCaseWithShell(
  path.join(__dirname, 'fixtures', 'with-linked-dep'),
  `
    run esy build

    # package "dep" should be visible in all envs
    assertStdout "esy dep" "dep"
    assertStdout "esy b dep" "dep"
    assertStdout "esy x dep" "dep"

    assertStdout "esy x with-linked-dep" "with-linked-dep"

    info "this SHOULD NOT rebuild dep"
    run esy build

    touch dep/dummy
    info "this SHOULD rebuild dep"
    run esy build
  `,
  {snapshotExecutionTrace: true},
);
