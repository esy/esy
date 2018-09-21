// @flow

const path = require('path');
const fs = require('fs-extra');

const {createTestSandbox, promiseExec, skipSuiteOnWindows} = require('../test/helpers');
const fixture = require('./fixture.js');

skipSuiteOnWindows('#301');

describe('ejected command-env', () => {
  it('check that `esy build` ejects a command-env which contains deps and devDeps in $PATH', async () => {
    const p = await createTestSandbox(...fixture.simpleProject);
    await p.esy('build');

    await expect(
      promiseExec('. ./node_modules/.cache/_esy/build/bin/command-env && dep.exe', {
        cwd: p.projectPath,
      }),
    ).resolves.toEqual({stdout: '__dep__\n', stderr: ''});

    await expect(
      promiseExec('. ./node_modules/.cache/_esy/build/bin/command-env && devDep.exe', {
        cwd: p.projectPath,
      }),
    ).resolves.toEqual({stdout: '__devDep__\n', stderr: ''});
  });
});
