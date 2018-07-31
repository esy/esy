// @flow

const path = require('path');
const fs = require('fs-extra');

const {genFixture, promiseExec, skipSuiteOnWindows} = require('../test/helpers');
const fixture = require('./fixture.js');

skipSuiteOnWindows("#301");

describe('Common - command-env', () => {
  it('generates valid environmenmt with deps and devdeps in $PATH', async () => {
    const p = await genFixture(...fixture.simpleProject);
    await p.esy('build');

    const commandEnv = (await p.esy('command-env')).stdout;

    await fs.writeFile(path.join(p.projectPath, 'command-env'), commandEnv);

    await expect(
      promiseExec('. ./command-env && dep', {
        cwd: p.projectPath,
      }),
    ).resolves.toEqual({stdout: '__dep__\n', stderr: ''});

    await expect(
      promiseExec('. ./command-env && devDep', {
        cwd: p.projectPath,
      }),
    ).resolves.toEqual({stdout: '__devDep__\n', stderr: ''});
  });
});
