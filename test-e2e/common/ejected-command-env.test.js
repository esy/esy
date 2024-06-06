// @flow

const path = require('path');
const fs = require('fs-extra');

const {createTestSandbox, promiseExec, skipSuiteOnWindows} = require('../test/helpers');
const fixture = require('./fixture.js');

// This test is not expected to work on Windows
// because it command-env works only with bash
// While it's a feature that may help users
// with MSYS2 or Cygwin, we don't have a validated
// usecase, where a workaround is not possible.
// See issue #301 for more details
skipSuiteOnWindows('#301');

describe('ejected command-env', () => {
  it('check that `esy build` ejects a command-env which contains deps and devDeps in $PATH', async () => {
    const p = await createTestSandbox();
    await p.fixture(...fixture.makeSimpleProject(p));
    await p.esy('install');
    await p.esy('build');

    await expect(
      promiseExec('. ./_esy/default/bin/command-env && dep.cmd', {
        cwd: p.projectPath,
      }),
    ).resolves.toEqual({stdout: '__dep__\n', stderr: ''});

    await expect(
      promiseExec('. ./_esy/default/bin/command-env && devDep.cmd', {
        cwd: p.projectPath,
      }),
    ).resolves.toEqual({stdout: '__devDep__\n', stderr: ''});
  });
});
