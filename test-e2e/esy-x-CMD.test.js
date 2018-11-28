// @flow

const os = require('os');
const path = require('path');
const fs = require('fs-extra');

const helpers = require('./test/helpers');
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
          buildEnv: {
            [`${name}__buildvar`]: `${name}__buildvar__value`,
          },
          exportedEnv: {
            [`${name}__local`]: {val: `${name}__local__value`},
            [`${name}__global`]: {val: `${name}__global__value`, scope: 'global'},
          },
        },
      }),

      dummyExecutable(name),
    );
  }

  async function createTestSandbox() {
    const p = await helpers.createTestSandbox();
    const name = 'root';
    await p.fixture(
      packageJson({
        name,
        version: '1.0.0',
        esy: {
          install: [
            'cp #{self.root / self.name}.js #{self.bin / self.name}.js',
            buildCommand(p, '#{self.bin / self.name}.js'),
          ],
          buildEnv: {
            [`${name}__buildvar`]: `${name}__buildvar__value`,
          },
          exportedEnv: {
            [`${name}__local`]: {val: `${name}__local__value`},
            [`${name}__global`]: {val: `${name}__global__value`, scope: 'global'},
          },
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
      dummyExecutable(name),
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
      stdout: '__root__' + os.EOL,
      stderr: '',
    });
  });

  it('runs commands defined in dependencies', async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy('x dep.cmd')).resolves.toEqual({
      stdout: '__dep__' + os.EOL,
      stderr: '',
    });
  });

  it('runs commands defined in devDependencies', async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy('x devDep.cmd')).resolves.toEqual({
      stdout: '__devDep__' + os.EOL,
      stderr: '',
    });
  });

  it('runs commands defined in linked dependencies', async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy('x linkedDep.cmd')).resolves.toEqual({
      stdout: '__linkedDep__' + os.EOL,
      stderr: '',
    });
  });

  it('builds (and rebuilds) root before running a command', async () => {
    const p = await createTestSandbox();
    await p.esy('install');

    await expect(p.esy('x root.cmd')).resolves.toMatchObject({
      stdout: '__root__' + os.EOL,
    });

    await fs.writeFile(
      path.join(p.projectPath, 'root.js'),
      'console.log("__CHANGED__");',
    );

    await expect(p.esy('x root.cmd')).resolves.toMatchObject({
      stdout: '__CHANGED__' + os.EOL,
    });
  });

  it('builds (and rebuilds) linked packages before running a command', async () => {
    const p = await createTestSandbox();
    await p.esy('install');

    await expect(p.esy('x linkedDep.cmd')).resolves.toMatchObject({
      stdout: '__linkedDep__' + os.EOL,
    });

    await fs.writeFile(
      path.join(p.projectPath, 'linkedDep', 'linkedDep.js'),
      'console.log("__CHANGED__");',
    );

    await expect(p.esy('x linkedDep.cmd')).resolves.toMatchObject({
      stdout: '__CHANGED__' + os.EOL,
    });
  });

  it('sees the exportedEnv of the root package', async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy(`x bash -c 'echo $root__local'`)).resolves.toMatchObject({
      stdout: 'root__local__value' + os.EOL,
    });
  });

  it('sees the exportedEnv of the dependency', async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy(`x bash -c 'echo $dep__local'`)).resolves.toMatchObject({
      stdout: 'dep__local__value' + os.EOL,
    });
  });

  it('sees the exportedEnv of the devDependency', async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy(`x bash -c 'echo $devDep__local'`)).resolves.toMatchObject({
      stdout: 'devDep__local__value' + os.EOL,
    });
  });

  it('inherits outside environment', async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    process.env.X = '1';
    await expect(p.esy(`x bash -c 'echo $X'`)).resolves.toEqual({
      stdout: '1' + os.EOL,
      stderr: '',
    });

    process.env.X = '2';
    await expect(p.esy(`x bash -c 'echo $X'`)).resolves.toEqual({
      stdout: '2' + os.EOL,
      stderr: '',
    });

    process.env = prevEnv;
  });

  it(`preserves exit code of the command it runs`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy("x bash -c 'exit 1'")).rejects.toMatchObject({
      code: 1,
    });
    await expect(p.esy("x bash -c 'exit 7'")).rejects.toMatchObject({
      code: 7,
    });
  });

  it(`can be invoked from project's subdirectories`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await fs.mkdir(path.join(p.projectPath, 'subdir'));
    await fs.writeFile(path.join(p.projectPath, 'subdir', 'X'), '');

    p.cd('./subdir');
    await expect(p.esy('x ls -1')).resolves.toMatchObject({
      stdout: 'X' + os.EOL,
    });
  });
});
