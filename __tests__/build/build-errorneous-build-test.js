/**
 * @flow
 */

import {defineTestCaseWithShell} from './utils';

defineTestCaseWithShell(
  'errorneous-build',
  `
    runAndExpectFailure esy build
  `,
);
