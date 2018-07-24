// @flow

const path = require('path');

const {initFixture, promiseExec} = require('../test/helpers');

it('Common - release', async () => {
  jest.setTimeout(300000);
  expect.assertions(6);

  const p = await initFixture(path.join(__dirname, 'fixtures/release'));

  await expect(p.esy('install')).resolves.not.toThrow();
  await expect(p.esy('release')).resolves.not.toThrow();

  // npm commands are run in the _release folder
  await expect(p.npm('pack')).resolves.not.toThrow();
  await expect(p.npm('-g install ./release-*.tgz')).resolves.not.toThrow();

  await expect(
    promiseExec(path.join(p.npmPrefixPath, 'bin', 'release.exe'), {
      env: {...process.env, NAME: 'ME'},
    }),
  ).resolves.toEqual({
    stdout: 'RELEASE-HELLO-FROM-ME\n',
    stderr: '',
  });

  await expect(
    promiseExec(path.join(p.npmPrefixPath, 'bin', 'release-dep.exe')),
  ).resolves.toEqual({
    stdout: 'RELEASE-DEP-HELLO\n',
    stderr: '',
  });
});
