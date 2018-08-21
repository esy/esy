// @flow

const path = require('path');
const fs = require('fs-extra');

const {createTestSandbox, skipSuiteOnWindows} = require('../test/helpers');
const fixture = require('./fixture.js');

skipSuiteOnWindows();

describe('Common - x anycmd', () => {
  let p;
  let prevEnv = {...process.env};

  beforeEach(async () => {
    p = await createTestSandbox(...fixture.simpleProject);
    await p.esy('build');
  });

  it('normal case works', async () => {
    await expect(p.esy('x dep')).resolves.toEqual({
      stdout: '__dep__\n',
      stderr: '',
    });
    await expect(p.esy('x devDep')).resolves.toEqual({
      stdout: '__devDep__\n',
      stderr: '',
    });
  });

  it('Make sure we can pass environment from the outside dynamically', async () => {
    expect.assertions(2);

    process.env.X = '1';
    await expect(p.esy('x bash -c "echo $X"')).resolves.toEqual({
      stdout: '1\n',
      stderr: '',
    });

    process.env.X = '2';
    await expect(p.esy('x bash -c "echo $X"')).resolves.toEqual({
      stdout: '2\n',
      stderr: '',
    });

    process.env = prevEnv;
  });

  it('Make sure exit code is preserved', async () => {
    expect.assertions(2);

    await expect(p.esy("x bash -c 'exit 1'")).rejects.toEqual(
      expect.objectContaining({code: 1}),
    );
    await expect(p.esy("x bash -c 'exit 7'")).rejects.toEqual(
      expect.objectContaining({code: 7}),
    );
  });

  it('Make sure we can run commands out of subdirectories', async () => {
    expect.assertions(1);

    await fs.mkdir(path.join(p.projectPath, 'subdir'));
    await fs.writeFile(path.join(p.projectPath, 'subdir', 'X'), '');

    await expect(
      p.esy('x ls -1', {cwd: path.join(p.projectPath, 'subdir')}),
    ).resolves.toEqual(expect.objectContaining({stdout: 'X\n'}));
  });
});
