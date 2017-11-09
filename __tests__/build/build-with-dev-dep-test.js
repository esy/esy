/**
 * @flow
 */

jest.setTimeout(200000);

import * as path from 'path';
import {initFixtureSync, readDirectory, cleanUp} from '../release/utils';

const fixture = initFixtureSync(path.join(__dirname, 'fixtures', 'with-dev-dep'));

test(`build ${fixture.description}`, async function() {
  const buildStdout = await fixture.esy(['build'], {cwd: fixture.project});
  expect(buildStdout).toMatchSnapshot('build stdout');

  const esyPrefixDir = await readDirectory(path.join(fixture.esyPrefix));
  expect(esyPrefixDir).toMatchSnapshot('esy prefix dir');

  const esyLocalPrefixDir = await readDirectory(fixture.localEsyPrefix);
  expect(esyLocalPrefixDir).toMatchSnapshot('esy local prefix dir');

  // dep executable is available in command-env
  const depExecStdout = await fixture.esy(['dep'], {cwd: fixture.project});
  expect(depExecStdout).toMatchSnapshot('dep exec stdout');

  // dev-dep executable is available in command-env
  const devDepExecStdout = await fixture.esy(['dev-dep'], {cwd: fixture.project});
  expect(devDepExecStdout).toMatchSnapshot('dev-dep exec stdout');

  // dev-dep executable is not available in build-env
  expectError(
    fixture.esy(['build', 'which', 'dev-dep'], {
      cwd: fixture.project,
    }),
  );
});

async function expectError(promise) {
  try {
    await promise;
  } catch (err) {
    return err;
  }
  expect(false).toBe(true);
}

afterAll(cleanUp);
