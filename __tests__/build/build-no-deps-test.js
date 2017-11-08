/**
 * @flow
 */

jest.setTimeout(200000);

import * as path from 'path';
import {initFixtureSync, readDirectory, cleanUp} from '../release/utils';

const fixture = initFixtureSync(path.join(__dirname, 'fixtures', 'no-deps'));

test(`build ${fixture.description}`, async function() {
  const buildStdout = await fixture.esy(['build'], {cwd: fixture.project});
  expect(buildStdout).toMatchSnapshot('build stdout');

  const esyPrefixDir = await readDirectory(path.join(fixture.esyPrefix));
  expect(esyPrefixDir).toMatchSnapshot('esy prefix dir');

  const esyLocalPrefixDir = await readDirectory(fixture.localEsyPrefix);
  expect(esyLocalPrefixDir).toMatchSnapshot('esy local prefix dir');
});

afterAll(cleanUp);
