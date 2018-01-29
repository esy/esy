/**
 * @flow
 */

import * as path from 'path';
import {defineTestCaseWithShell} from '../utils';

defineTestCaseWithShell(
  path.join(__dirname, 'fixtures', 'symlinks-into-dep'),
  `
    run esy build

    # package "subdep" should be visible in all envs
    assertStdout "esy subdep" "subdep"
    assertStdout "esy b subdep" "subdep"
    assertStdout "esy x subdep" "subdep"

    # same for package "dep" but it should reuse the impl of "subdep"
    assertStdout "esy dep" "subdep"
    assertStdout "esy b dep" "subdep"
    assertStdout "esy x dep" "subdep"

    # and root package links into "dep" which links into "subdep"
    assertStdout "esy x symlinks-into-dep" "subdep"

    ls ../esy/3/i
    # check that link is here
    storeTarget=$(readlink ../esy/3/i/dep-1.0.0-*/bin/dep)
    if [[ "$storeTarget" != $ESY_TEST__PREFIX* ]]; then
      failwith "invalid symlink target: $storeTarget"
    fi

    # export build from store
    run esy export-build ../esy/3/i/dep-1.0.0-*
    cd _export
    run tar xzf dep-1.0.0-*.tar.gz
    cd ../

    # check symlink target for exported build
    exportedTarget=$(readlink _export/dep-1.0.0-*/bin/dep)
    if [[ "$exportedTarget" != ________* ]]; then
      failwith "invalid symlink target: $exportedTarget"
    fi

    # drop & import
    run rm -rf ../esy/3/i/dep-1.0.0
    run esy import-build ./_export/dep-1.0.0-*.tar.gz

    # check symlink target for imported build
    importedTarget=$(readlink ../esy/3/i/dep-1.0.0-*/bin/dep)
    if [[ "$importedTarget" != $ESY_TEST__PREFIX* ]]; then
      failwith "invalid symlink target: $exportedTarget"
    fi

  `,
);
