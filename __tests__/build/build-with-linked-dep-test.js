/**
 * @flow
 */

jest.setTimeout(200000);

import * as path from 'path';
import * as fs from '../../src/lib/fs';
import {initFixtureSync, readDirectory, cleanUp} from '../release/utils';

const fixture = initFixtureSync(path.join(__dirname, 'fixtures', 'with-linked-dep'));

fs.copydirSync(
  path.join(__dirname, 'fixtures', 'dep-of-with-linked-dep'),
  path.join(fixture.root, 'dep-of-with-linked-dep'),
);

test(`build ${fixture.description}`, async function() {
  const buildStdout = await fixture.esy(['build'], {cwd: fixture.project});
  expect(buildStdout).toMatchSnapshot('build stdout');

  const esyPrefixDir = await readDirectory(path.join(fixture.esyPrefix));
  expect(esyPrefixDir).toMatchSnapshot('esy prefix dir');

  const esyLocalPrefixDir = await readDirectory(fixture.localEsyPrefix);
  expect(esyLocalPrefixDir).toMatchSnapshot('esy local prefix dir');

  // dep executable is available in env
  const depExecStdout = await fixture.esy(['dep-of-with-linked-dep'], {
    cwd: fixture.project,
  });
  expect(depExecStdout).toMatchSnapshot('dep exec stdout');
});

afterAll(cleanUp);
