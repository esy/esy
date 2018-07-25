// @flow

const path = require('path');
const fs = require('fs-extra');

const {initFixture, promiseExec} = require('../test/helpers');
const ESYCOMMAND = require.resolve('../../bin/esy');

describe('Common - anycmd', () => {
  let p;
  let prevEnv = {...process.env};

  beforeAll(async () => {
    p = await initFixture(path.join(__dirname, './fixtures/simple-project'));
    await p.esy('build');
  });

  it('normal case works', async () => {
    expect.assertions(2);

    await expect(p.esy('dep')).resolves.toEqual({
      stdout: 'dep\n',
      stderr: '',
    });
    await expect(p.esy('dev-dep')).resolves.toEqual({
      stdout: expect.stringMatching('dev-dep\n'),
      stderr: '',
    });
  });

  it('Make sure we can pass environment from the outside dynamically', async () => {
    expect.assertions(2);

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
    expect.assertions(2);

    await expect(p.esy("esy bash -c 'exit 1'")).rejects.toEqual(
      expect.objectContaining({code: 1}),
    );
    await expect(p.esy("esy bash -c 'exit 7'")).rejects.toEqual(
      expect.objectContaining({code: 7}),
    );
  });

  it('Make sure we can run commands out of subdirectories', async () => {
    expect.assertions(1);

    await fs.mkdir(path.join(p.projectPath, 'subdir'));
    await fs.writeFile(path.join(p.projectPath, 'subdir', 'X'), '');

    await expect(
      promiseExec(`${ESYCOMMAND} ls -1`, {
        cwd: path.join(p.projectPath, 'subdir'),
      }),
    ).resolves.toEqual(expect.objectContaining({stdout: 'X\n'}));
  });
});
