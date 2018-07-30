// @flow

const path = require('path');
const fs = require('fs-extra');

const {genFixture, promiseExec} = require('../test/helpers');
const fixture = require('./fixture.js');

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
    ).resolves.toEqual({stdout: 'dep\n', stderr: ''});

    await expect(
      promiseExec('. ./command-env && dev-dep', {
        cwd: p.projectPath,
      }),
    ).resolves.toEqual({stdout: 'dev-dep\n', stderr: ''});
  });
});
