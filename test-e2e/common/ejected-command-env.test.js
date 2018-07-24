// @flow

const path = require('path');
const fs = require('fs-extra');

const {initFixture, promiseExec} = require('../test/helpers');

describe('Common - ejected command env', () => {
  it('Check that `esy build` ejects a command-env which contains deps and devDeps in $PATH', async () => {
    expect.assertions(2);
    const p = await initFixture(path.join(__dirname, 'fixtures/simple-project'));
    await p.esy('build');

    await expect(
      promiseExec('source ./node_modules/.cache/_esy/build/bin/command-env && dep', {
        cwd: p.projectPath,
      }),
    ).resolves.toEqual({stdout: 'dep\n', stderr: ''});

    await expect(
      promiseExec('source ./node_modules/.cache/_esy/build/bin/command-env && dev-dep', {
        cwd: p.projectPath,
      }),
    ).resolves.toEqual({stdout: 'dev-dep\n', stderr: ''});
  });
});
