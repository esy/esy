// @flow

const os = require('os');
const path = require('path');

const helpers = require('./test/helpers');
const {packageJson, dir, file, dummyExecutable, buildCommand} = helpers;

helpers.skipSuiteOnWindows();

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

describe(`'esy build CMD' invocation`, () => {

  async function createTestSandbox() {
    const p = await helpers.createTestSandbox();
    const name = 'root';
    await p.fixture(
      packageJson({
        name,
        version: '1.0.0',
        esy: {
          build: [
            ['cp', '#{self.name}.js', '#{self.target_dir / self.name}.js'],
            helpers.buildCommand(p, '#{self.target_dir / self.name}.js'),
          ],
          install: [
            `cp #{self.target_dir / self.name}.cmd #{self.bin / self.name}.cmd`,
            `cp #{self.target_dir / self.name}.js #{self.bin / self.name}.js`,
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
      createPackage(p, {name: 'dep', dependencies: {depOfDep: 'path:../depOfDep'}}),
      createPackage(p, {name: 'depOfDep'}),
      createPackage(p, {name: 'linkedDep'}),
      createPackage(p, {name: 'devDep'}),
    );
    return p;
  }

  it(`invokes commands in build environment`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy('build dep.cmd')).resolves.toEqual({
      stdout: '__dep__' + os.EOL,
      stderr: '',
    });
  });

  it(`can invoke commands defined in devDependencies`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy('build devDep.cmd')).resolves.toMatchObject({
      stdout: '__devDep__' + os.EOL,
      stderr: '',
    });
  });

  it(`cannot invoke commands defined in devDependencies if --release is passed`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy('build --release devDep.cmd')).rejects.toMatchObject({
      stdout: '',
      stderr: expect.stringMatching('unable to resolve command: devDep.cmd'),
    });
  });

  it(`builds dependencies before running a command`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');

    await p.esy('build dep.cmd');
  });

  it(`builds linked dependencies before running a command`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');

    await p.esy('build linkedDep.cmd');
  });

  it(`has 'esy b CMD' shortcut`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy('b dep.cmd')).resolves.toEqual({
      stdout: '__dep__' + os.EOL,
      stderr: '',
    });
  });

  it(`sees buildEnv of the package`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy(`b bash -c 'echo $root__buildvar'`)).resolves.toEqual({
      stdout: 'root__buildvar__value' + os.EOL,
      stderr: '',
    });
  });

  it(`preserves exit code of the command it runs`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    // make sure exit code is preserved
    await expect(p.esy("b bash -c 'exit 1'")).rejects.toEqual(
      expect.objectContaining({code: 1}),
    );
    await expect(p.esy("b bash -c 'exit 7'")).rejects.toEqual(
      expect.objectContaining({code: 7}),
    );
  });
});

describe(`'esy build CMD' invocation ("buildDev" config at the root)`, () => {

  async function createTestSandbox() {
    const p = await helpers.createTestSandbox();
    const name = 'root';
    await p.fixture(
      packageJson({
        name,
        version: '1.0.0',
        esy: {
          build: [
            ['cp', '#{self.name}.js', '#{self.target_dir / self.name}.js'],
            helpers.buildCommand(p, '#{self.target_dir / self.name}.js'),
          ],
          buildDev: [
            ['cp', '#{self.name}-dev.js', '#{self.target_dir / self.name}.js'],
            helpers.buildCommand(p, '#{self.target_dir / self.name}.js'),
          ],
          install: [
            `cp #{self.target_dir / self.name}.cmd #{self.bin / self.name}.cmd`,
            `cp #{self.target_dir / self.name}.js #{self.bin / self.name}.js`,
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
      dummyExecutable(name + '-dev'),
      createPackage(p, {name: 'dep', dependencies: {depOfDep: 'path:../depOfDep'}}),
      createPackage(p, {name: 'depOfDep'}),
      createPackage(p, {name: 'linkedDep'}),
      createPackage(p, {name: 'devDep'}),
    );
    return p;
  }

  it(`can access dependencies`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy('build dep.cmd')).resolves.toEqual({
      stdout: '__dep__' + os.EOL,
      stderr: '',
    });
  });

  it(`can access dependencies if --release is passed`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy('build dep.cmd')).resolves.toEqual({
      stdout: '__dep__' + os.EOL,
      stderr: '',
    });
  });

  it(`can access devDependencies`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy('build devDep.cmd')).resolves.toEqual({
      stdout: '__devDep__' + os.EOL,
      stderr: '',
    });
  });

  it(`cannot access devDependencies if --release is passed`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy('build --release devDep.cmd')).rejects.toMatchObject({
      message: expect.stringMatching('unable to resolve command: devDep.cmd')
    });
  });

});
