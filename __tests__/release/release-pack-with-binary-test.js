/**
 * @flow
 */

jest.setTimeout(200000);

import testWithBinary from './fixtures/with-binary/test';

const testCase = testWithBinary({releaseType: 'pack'});

test(testCase.description, testCase.test);
afterAll(testCase.cleanUp);
