// @flow

const path = require('path');
const fs = require('fs-extra');

const helpers = require('../test/helpers');
const {packageJson, dir, file, dummyExecutable, buildCommand} = helpers;

helpers.skipSuiteOnWindows();

describe(`'esy x CMD' invocation`, () => {
  let prevEnv = {...process.env};

  function createPackage(p, name) {
    return dir(
      name,
      packageJson({
        name,
        version: '1.0.0',
        esy: {
          install: [
            'cp #{self.root / self.name}.js #{self.bin / self.name}.js',
            buildCommand(p, '#{self.bin / self.name}.js'),
          ],
        },
      }),

      dummyExecutable(name),
    );
  }

  async function createTestSandbox() {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {
          install: [
            'cp #{self.root / self.name}.js #{self.bin / self.name}.js',
            buildCommand(p, '#{self.bin / self.name}.js'),
          ],
        },
        dependencies: {
          dep: 'path:./dep',
          linkedDep: '*',
        },
        devDependencies: {
          devDep: 'path:./devDep',
        },
        resolutions: {
          linkedDep: 'link:./linkedDep',
        },
      }),
      dummyExecutable('root'),
      createPackage(p, 'dep'),
      createPackage(p, 'linkedDep'),
      createPackage(p, 'devDep'),
    );
    return p;
  }

  it('runs commands defined in root package', async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy('x root.cmd')).resolves.toEqual({
      stdout: '__root__\n',
      stderr: '',
    });
  });

  it('runs commands defined in dependencies', async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy('x dep.cmd')).resolves.toEqual({
      stdout: '__dep__\n',
      stderr: '',
    });
  });

  it('runs commands defined in devDependencies', async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy('x devDep.cmd')).resolves.toEqual({
      stdout: '__devDep__\n',
      stderr: '',
    });
  });

  it('runs commands defined in linked dependencies', async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy('x linkedDep.cmd')).resolves.toEqual({
      stdout: '__linkedDep__\n',
      stderr: '',
    });
  });

  it('builds (and rebuilds) root before running a command', async () => {
    const p = await createTestSandbox();
    await p.esy('install');

    await expect(p.esy('x root.cmd')).resolves.toMatchObject({
      stdout: '__root__\n',
    });

    await fs.writeFile(
      path.join(p.projectPath, 'root.js'),
      'console.log("__CHANGED__");',
    );

    await expect(p.esy('x root.cmd')).resolves.toMatchObject({
      stdout: '__CHANGED__\n',
    });
  });

  it('builds (and rebuilds) linked packages before running a command', async () => {
    const p = await createTestSandbox();
    await p.esy('install');

    await expect(p.esy('x linkedDep.cmd')).resolves.toMatchObject({
      stdout: '__linkedDep__\n',
    });

    await fs.writeFile(
      path.join(p.projectPath, 'linkedDep', 'linkedDep.js'),
      'console.log("__CHANGED__");',
    );

    await expect(p.esy('x linkedDep.cmd')).resolves.toMatchObject({
      stdout: '__CHANGED__\n',
    });
  });

  it('inherits outside environment', async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

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

  it(`preserves exit code of the command it runs`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy("x bash -c 'exit 1'")).rejects.toEqual(
      expect.objectContaining({code: 1}),
    );
    await expect(p.esy("x bash -c 'exit 7'")).rejects.toEqual(
      expect.objectContaining({code: 7}),
    );
  });

  it(`can be invoked from project's subdirectories`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await fs.mkdir(path.join(p.projectPath, 'subdir'));
    await fs.writeFile(path.join(p.projectPath, 'subdir', 'X'), '');

    p.cd('./subdir');
    await expect(p.esy('x ls -1')).resolves.toEqual(
      expect.objectContaining({stdout: 'X\n'}),
    );
  });
});
