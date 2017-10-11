/**
 * @flow
 */

jest.setTimeout(200000);

import * as os from 'os';
import * as path from 'path';
import {
  readDirectory,
  cleanUp,
  esyBin,
  runIn,
  packAndNpmInstallGlobal,
  initFixtureSync,
} from '../../utils';

export default function initTest(params: {releaseType: string}) {
  const fixture = initFixtureSync(__dirname);
  const description = `esy release ${params.releaseType}: ${fixture.description}`;

  const releaseDir = params.releaseType === 'bin'
    ? `bin-${os.platform()}`
    : params.releaseType;

  const test = async () => {
    await runIn(fixture.project, 'npm', 'install');
    expect(
      await runIn(fixture.project, esyBin, 'release', params.releaseType),
    ).toMatchSnapshot('release stdout');

    expect(await readDirectory(fixture.project, '_release')).toMatchSnapshot('release');

    expect(
      await packAndNpmInstallGlobal(fixture, '_release', releaseDir),
    ).toMatchSnapshot('installation stdout');

    expect(await readDirectory(fixture.npmPrefix)).toMatchSnapshot('installation');
  };

  return {cleanUp, description, test};
}
