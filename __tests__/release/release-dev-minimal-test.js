/**
 * @flow
 */

jest.setTimeout(200000);

import * as path from 'path';
import {
  createProject,
  readDirectory,
  cleanUp,
  esyBin,
  runIn,
  run,
  file,
  directory,
  packAndNpmInstallGlobal,
  initFixtureSync,
} from './utils';

const fixture = initFixtureSync(path.join(__dirname, 'fixtures', 'minimal'));

afterAll(cleanUp);

test(`esy release dev: ${fixture.description}`, async function() {
  await runIn(fixture.project, 'npm', 'install');
  await runIn(fixture.project, esyBin, 'release', 'dev');

  expect(await readDirectory(fixture.project, '_release')).toMatchSnapshot('release');

  await packAndNpmInstallGlobal(fixture, '_release', 'dev');

  expect(await readDirectory(fixture.npmPrefix)).toMatchSnapshot('installation');
});
