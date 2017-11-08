/**
 * @flow
 */

import * as path from 'path';
import {initFixtureSync, readDirectory, cleanUp} from '../release/utils';

const fixture = initFixtureSync(path.join(__dirname, 'fixtures', 'errorneous-build'));

test(`build ${fixture.description}`, async function() {
  try {
    await fixture.esy(['build'], {cwd: fixture.project});
  } catch(err) {
    return;
  }
  // fail if we are here
  expect(false).toBe(true);
});

afterAll(cleanUp);
