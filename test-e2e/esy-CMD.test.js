// @flow

const path = require('path');
const fs = require('fs-extra');
const os = require('os');

const helpers = require('./test/helpers');
const {test, isWindows, packageJson, dir, file, dummyExecutable, buildCommand} = helpers;

helpers.skipSuiteOnWindows();

describe(`'esy CMD' invocation`, () => {
  let prevEnv = {...process.env};

  function createPackage(p, {name, dependencies}: {name: string, dependencies?: Object}) {
    return dir(
      name,
      packageJson({
        name,
        version: '1.0.0',
        dependencies,
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
      createPackage(p, {name: 'dep'}),
      createPackage(p, {name: 'devDep'}),
    );
    return p;
  }

  test(`can execute commands defined in sandbox dependencies`, async () => {
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

  test(`fails if project is not installed`, async () => {
    const p = await createTestSandbox();
    await expect(p.esy('dep.cmd')).rejects.toMatchObject({
      message: expect.stringMatching(
        'error: project is missing a lock, run `esy install`',
      ),
    });
  });

  test(`can execute commands defined in sandbox dependencies, dependencies will be built`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('dep.cmd');
  });

  test(`can execute commands defined in sandbox devDependencies, devDependencies will be built`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('devDep.cmd');
  });

  // TODO On some machines, ulimit is not present as a binary for POSIX compatibility.
  // Esy should ideally not try to fork/exec shell built-ins
  test.disableIf(true)('ensures the RLIMIT_NOFILE was set', async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    const { stdout } = await p.run(`ulimit -Sn 2048 && ${helpers.ESY} sh -c "ulimit -Sn"`);
    const result = stdout.trim();
    expect(result).toEqual("4096");
  })

  test('inherits the outside environment', async () => {
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

  test('preserves exit code of the command test runs', async () => {
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

  test(`-p: execute commands in a specified package's environment`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await expect(p.esy('-p dep echo "#{self.name}"')).resolves.toEqual({
      stdout: 'dep\n',
      stderr: '',
    });
  });

  test(`-p: requires a command`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await expect(p.esy('-p dep')).rejects.toMatchObject({
      message: expect.stringMatching(
				"esy: missing a command to execute \\(required when '-p <name>' is passed\\)"
			)
    });
  });

  it(`-p: -C flag sets CWD to a specified dependency's root`, async () => {
    const p = await createTestSandbox();

    await fs.mkdir(path.join(p.projectPath, 'dep', 'subdir'));
    await fs.writeFile(path.join(p.projectPath, 'dep', 'subdir', 'X'), '');

    await p.esy('install');

    await expect(p.esy('-C -p dep ls -1 ./subdir')).resolves.toMatchObject({
      stdout: 'X' + os.EOL,
    });
  });

  test(`can be invoked from project's subdirectories`, async () => {
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

  test(`doesn't wait for linked packages to be built`, async () => {
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

  test.disableIf(isWindows)(`exports the path to the root package config to the env`, async () => {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      file('package.json', JSON.stringify({
        name: 'package',
        version: '1.0.0',
      }, null, 2)),
      file('dev.json', JSON.stringify({
        name: 'dev',
        version: '1.0.0',
      }, null, 2))
    );

    // check `esy ...`
    {
      await p.esy('install');
      const {stdout} = await p.esy("bash -c 'echo $ESY__ROOT_PACKAGE_CONFIG_PATH'");
      expect(stdout.trim()).toBe(path.join(p.projectPath, 'package.json'));
    }

    // check `esy @dev ...`
    {
      await p.esy('@dev install');
      const {stdout} = await p.esy("@dev bash -c 'echo $ESY__ROOT_PACKAGE_CONFIG_PATH'");
      expect(stdout.trim()).toBe(path.join(p.projectPath, 'dev.json'));
    }
  });

  test.disableIf(isWindows)(`nested esy invocations autoconfigure with the right root package config`, async () => {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      file('package.json', JSON.stringify({
        name: 'package',
        version: '1.0.0',
      }, null, 2)),
      file('dev.json', JSON.stringify({
        name: 'dev',
        version: '1.0.0',
      }, null, 2))
    );

    // check `esy ...`
    {
      await p.esy('install');
      const {stdout} = await p.esy("esy echo '#{self.name}'");
      expect(stdout.trim()).toBe('package');
    }

    // check `esy @dev ...`
    {
      await p.esy('@dev install');
      const {stdout} = await p.esy("@dev esy echo '#{self.name}'");
      expect(stdout.trim()).toBe('dev');
    }
  });

  test.disableIf(isWindows)(`nested esy invocations give the right error messages`, async () => {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      file('package.json', JSON.stringify({
        name: 'package',
        version: '1.0.0',
      }, null, 2)),
      file('dev.json', JSON.stringify({
        name: 'dev',
        version: '1.0.0',
      }, null, 2))
    );

    // check the `esy install` error message.
    {
      await expect(p.esy('dep.cmd')).rejects.toMatchObject({
        message: expect.stringMatching(
          'error: project is missing a lock, run `esy install`',
        ),
      });
    }

    // install, to unblock testing sandbox install err message
    {
      await p.esy('install');
      const {stdout} = await p.esy("esy echo '#{self.name}'");
      expect(stdout.trim()).toBe('package');
    }

    // check `esy '@dev' install` error message
    {
      await expect(p.esy('@dev dep.cmd')).rejects.toMatchObject({
        message: expect.stringMatching(
          'error: project is missing a lock, run `esy \'@dev\' install`',
        ),
      });
    }

    // check `esy @dev ...`
    {
      await p.esy('@dev install');
      const {stdout} = await p.esy("@dev esy echo '#{self.name}'");
      expect(stdout.trim()).toBe('dev');
    }
  });

});
