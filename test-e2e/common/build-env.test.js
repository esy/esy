// @flow

const path = require('path');
const fs = require('fs-extra');

const {genFixture, promiseExec} = require('../test/helpers');
const fixture = require('./fixture.js');

describe('Common - build-env', () => {
  it('generates an environment with deps in $PATH', async () => {
    const p = await genFixture(...fixture.simpleProject);
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
