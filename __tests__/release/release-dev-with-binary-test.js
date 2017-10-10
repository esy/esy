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
  initFixture,
} from './utils';

afterEach(cleanUp);

test('esy release dev: with "releasedBinaries"', async function() {
  const fixture = await initFixture(path.join(__dirname, 'fixtures', 'with-binary'));
  await runIn(fixture.project, 'npm', 'install');
  await runIn(fixture.project, esyBin, 'release', 'dev');

  expect(await readDirectory(fixture.project, '_release')).toMatchSnapshot('release');

  await packAndNpmInstallGlobal(fixture, '_release', 'dev');

  expect(await readDirectory(fixture.npmPrefix)).toMatchSnapshot('installation');

  const res = await run(path.join(fixture.npmPrefix, 'bin', 'say-hello.exe'));
  expect(res).toBe('HELLO');
});
