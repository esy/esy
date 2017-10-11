/**
 * @flow
 */

jest.setTimeout(200000);

import testMinimal from './fixtures/minimal/test';

const testCase = testMinimal({releaseType: 'pack'});

test(testCase.description, testCase.test);
afterAll(testCase.cleanUp);
