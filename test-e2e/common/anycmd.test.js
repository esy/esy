// @flow

const path = require('path');
const fs = require('fs-extra');
const os = require('os');

const helpers = require('../test/helpers');
const fixture = require('./fixture.js');

helpers.skipSuiteOnWindows();

describe('Common - anycmd', () => {
  let prevEnv = {...process.env};

  async function createTestSandbox() {
    const p = await helpers.createTestSandbox(...fixture.simpleProject);
    await p.esy('build');
    return p;
  }

  it('normal case works', async () => {
    const p = await createTestSandbox();
    await expect(p.esy('dep.cmd')).resolves.toEqual({
      stdout: '__dep__' + os.EOL,
      stderr: '',
    });
    await expect(p.esy('devDep.cmd')).resolves.toEqual({
      stdout: '__devDep__' + os.EOL,
      stderr: '',
    });
  });

  it('Make sure we can pass environment from the outside dynamically', async () => {
    process.env.X = '1';
    const p = await createTestSandbox();
    await expect(p.esy('bash -c "echo $X"')).resolves.toEqual({
      stdout: '1\n',
      stderr: '',
    });

    process.env.X = '2';
    await expect(p.esy('bash -c "echo $X"')).resolves.toEqual({
      stdout: '2\n',
      stderr: '',
    });

    process.env = prevEnv;
  });

  it('Make sure exit code is preserved', async () => {
    const p = await createTestSandbox();
    await expect(p.esy("bash -c 'exit 1'")).rejects.toEqual(
      expect.objectContaining({code: 1}),
    );
    await expect(p.esy("bash -c 'exit 7'")).rejects.toEqual(
      expect.objectContaining({code: 7}),
    );
  });

  it('Make sure we can run commands out of subdirectories', async () => {
    const p = await createTestSandbox();
    await fs.mkdir(path.join(p.projectPath, 'subdir'));
    await fs.writeFile(path.join(p.projectPath, 'subdir', 'X'), '');

    await expect(
      p.esy('ls -1', {cwd: path.join(p.projectPath, 'subdir')}),
    ).resolves.toEqual(expect.objectContaining({stdout: 'X\n'}));
  });
});
