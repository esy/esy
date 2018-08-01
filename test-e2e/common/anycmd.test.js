// @flow

const path = require('path');
const fs = require('fs-extra');
const os = require('os');

const {
  createTestSandbox,
  promiseExec,
  ESYCOMMAND,
  skipSuiteOnWindows,
} = require('../test/helpers');
const fixture = require('./fixture.js');

skipSuiteOnWindows();

describe('Common - anycmd', () => {
  let p;
  let prevEnv = {...process.env};

  beforeEach(async () => {
    p = await createTestSandbox(...fixture.simpleProject);
    await p.esy('build');
  });

  it('normal case works', async () => {
    await expect(p.esy('dep')).resolves.toEqual({
      stdout: '__dep__' + os.EOL,
      stderr: '',
    });
    await expect(p.esy('devDep')).resolves.toEqual({
      stdout: '__devDep__' + os.EOL,
      stderr: '',
    });
  });

  it('Make sure we can pass environment from the outside dynamically', async () => {
    process.env.X = '1';
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
    await expect(p.esy("bash -c 'exit 1'")).rejects.toEqual(
      expect.objectContaining({code: 1}),
    );
    await expect(p.esy("bash -c 'exit 7'")).rejects.toEqual(
      expect.objectContaining({code: 7}),
    );
  });

  it('Make sure we can run commands out of subdirectories', async () => {
    await fs.mkdir(path.join(p.projectPath, 'subdir'));
    await fs.writeFile(path.join(p.projectPath, 'subdir', 'X'), '');

    await expect(
      promiseExec(`${ESYCOMMAND} ls -1`, {
        cwd: path.join(p.projectPath, 'subdir'),
      }),
    ).resolves.toEqual(expect.objectContaining({stdout: 'X\n'}));
  });
});
