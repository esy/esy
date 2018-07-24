// @flow

const path = require('path');
const fs = require('fs-extra');

const {initFixture, promiseExec} = require('../test/helpers');

describe('Common - command-env', () => {
  it('generates valid environmenmt with deps and devdeps in $PATH', async () => {
    expect.assertions(2);
    const p = await initFixture(path.join(__dirname, 'fixtures/simple-project'));
    await p.esy('build');

    const commandEnv = (await p.esy('command-env')).stdout;

    await fs.writeFile(path.join(p.projectPath, 'command-env'), commandEnv);

    await expect(
      promiseExec('source ./command-env && dep', {
        cwd: p.projectPath,
      }),
    ).resolves.toEqual({stdout: 'dep\n', stderr: ''});

    await expect(
      promiseExec('source ./command-env && dev-dep', {
        cwd: p.projectPath,
      }),
    ).resolves.toEqual({stdout: 'dev-dep\n', stderr: ''});
  });
});
