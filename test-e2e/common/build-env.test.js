// @flow

const path = require('path');
const fs = require('fs-extra');

const {initFixture, promiseExec, skipTestSuiteOnWindows} = require('../test/helpers');

skipTestSuiteOnWindows("#301");

describe('Common - build-env', () => {
  it('generates an environment with deps in $PATH', async () => {
    expect.assertions(2);
    const p = await initFixture(path.join(__dirname, 'fixtures/simple-project'));
    await p.esy('build');

    const buildEnv = (await p.esy('build-env')).stdout;

    await fs.writeFile(path.join(p.projectPath, 'build-env'), buildEnv);

    await expect(
      promiseExec('. ./build-env && dep', {
        cwd: p.projectPath,
      }),
    ).resolves.toEqual({stdout: 'dep\n', stderr: ''});

    await expect(
      promiseExec('. ./build-env && dev-dep', {
        cwd: p.projectPath,
      }),
    ).rejects.toThrow();
  });
});
