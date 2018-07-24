// @flow

const path = require('path');

const {initFixture, promiseExec} = require('../test/helpers');

it('Common - release', async () => {
  jest.setTimeout(300000);
  expect.assertions(6);

  const p = await initFixture(path.join(__dirname, 'fixtures/release'));

  await expect(p.esy('install')).resolves.not.toThrow();
  await expect(p.esy('release')).resolves.not.toThrow();

  await expect(p.npm('pack')).resolves.not.toThrow();
  await expect(p.npm('-g install ./release-*.tgz')).resolves.not.toThrow();

  const release = await promiseExec('RELEASE-HELLO-FROM-ME', {
    env: {...process.env, NAME: 'ME'},
  });
  expect(release).toEqual({
    stdout: path.join(p.npmPrefixPath, 'bin', 'release.exe') + '\n',
    stderr: '',
  });
  const releaseDep = await promiseExec('RELEASE-DEP-HELLO');
  expect(releaseDep).toEqual({
    stdout: path.join(p.npmPrefixPath, 'bin', 'release-dep.exe') + '\n',
    stderr: '',
  });
});
