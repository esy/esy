// @flow

const path = require('path');
const fs = require('fs-extra');
const os = require('os');

const helpers = require('../test/helpers');
const {packageJson, dir, file, dummyExecutable, buildCommand} = helpers;

helpers.skipSuiteOnWindows();

describe(`'esy CMD' invocation`, () => {
  let prevEnv = {...process.env};

  async function createTestSandbox() {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      packageJson({
        name: 'simple-project',
        version: '1.0.0',
        dependencies: {
          dep: 'path:./dep',
        },
        devDependencies: {
          devDep: 'path:./devDep',
        },
      }),
      dir(
        'dep',
        packageJson({
          name: 'dep',
          version: '1.0.0',
          esy: {
            install: [
              'cp #{self.root / self.name}.js #{self.bin / self.name}.js',
              buildCommand(p, '#{self.bin / self.name}.js'),
            ],
          },
          dependencies: {},
        }),

        dummyExecutable('dep'),
      ),
      dir(
        'devDep',
        packageJson({
          name: 'devDep',
          version: '1.0.0',
          esy: {
            install: [
              'cp #{self.root / self.name}.js #{self.bin / self.name}.js',
              buildCommand(p, '#{self.bin / self.name}.js'),
            ],
          },
        }),
        dummyExecutable('devDep'),
      ),
    );
    return p;
  }

  it(`can execute commands defined in sandbox dependencies`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');
    await expect(p.esy('dep.cmd')).resolves.toEqual({
      stdout: '__dep__' + os.EOL,
      stderr: '',
    });
    await expect(p.esy('devDep.cmd')).resolves.toEqual({
      stdout: '__devDep__' + os.EOL,
      stderr: '',
    });
  });

  it(`can execute commands defined in sandbox dependencies, dependencies will be built`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('dep.cmd');
  });

  it(`can execute commands defined in sandbox devDependencies, devDependencies will be built`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('dep.cmd');
  });

  it('inherits the outside environment', async () => {
    process.env.X = '1';
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');
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
    await p.esy('install');
    await p.esy('build');
    await expect(p.esy("bash -c 'exit 1'")).rejects.toEqual(
      expect.objectContaining({code: 1}),
    );
    await expect(p.esy("bash -c 'exit 7'")).rejects.toEqual(
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
    await expect(p.esy('ls -1')).resolves.toEqual(
      expect.objectContaining({stdout: 'X\n'}),
    );
  });

  it(`doesn't wait for linked packages to be built`, async () => {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {
          dep: 'path:./dep',
        },
        resolutions: {
          dep: 'link:./dep',
        },
      }),
      dir(
        'dep',
        packageJson({
          name: 'dep',
          version: '1.0.0',
          esy: {
            build: 'false',
          },
          dependencies: {},
        }),
      ),
    );
    await p.esy('install');
    // just check that we don't faail on building 'dep'
    await p.esy('true');
  });
});
