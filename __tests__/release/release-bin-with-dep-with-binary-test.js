/**
 * @flow
 */

jest.setTimeout(200000);

import testWithDepWithBinary from './fixtures/with-dep-with-binary/test';

const testCase = testWithDepWithBinary({releaseType: 'bin'});

test(testCase.description, testCase.test);
afterAll(testCase.cleanUp);
