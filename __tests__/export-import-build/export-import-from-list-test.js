/**
 * @flow
 */

import * as path from 'path';
import {defineTestCaseWithShell} from '../utils';

defineTestCaseWithShell(
  path.join(__dirname, 'fixtures', 'symlinks-into-dep'),
  `
    run esy build
    run esy export-dependencies

    find _export -type f > list.txt
    run cat list.txt

    run rm -rf ../esy/3/i/*
    run ls -1 ../esy/3/i/

    run esy import-build --from ./list.txt

    run ls -1 ../esy/3/i/

  `,
  {snapshotExecutionTrace: true},
);
