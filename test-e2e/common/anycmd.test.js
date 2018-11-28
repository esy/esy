// @flow

const path = require('path');
const fs = require('fs-extra');
const os = require('os');

const helpers = require('../test/helpers');
const fixture = require('./fixture.js');

helpers.skipSuiteOnWindows();

describe(`'esy CMD' invocation`, () => {
  let prevEnv = {...process.env};

  async function createTestSandbox() {
    const p = await helpers.createTestSandbox();
    await p.fixture(...fixture.makeSimpleProject(p));
    await p.esy('install');
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

  it('inherits the outside environment', async () => {
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

  it('preserves exit code of the command it runs', async () => {
    const p = await createTestSandbox();
    await expect(p.esy("bash -c 'exit 1'")).rejects.toEqual(
      expect.objectContaining({code: 1}),
    );
    await expect(p.esy("bash -c 'exit 7'")).rejects.toEqual(
      expect.objectContaining({code: 7}),
    );
  });

  it(`can be invoked from project's subdirectories`, async () => {
    const p = await createTestSandbox();
    await fs.mkdir(path.join(p.projectPath, 'subdir'));
    await fs.writeFile(path.join(p.projectPath, 'subdir', 'X'), '');

    p.cd('./subdir');
    await expect(p.esy('ls -1')).resolves.toEqual(
      expect.objectContaining({stdout: 'X\n'}),
    );
  });
});
