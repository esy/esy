// @flow

const path = require('path');
const fs = require('fs-extra');
const os = require('os');

const helpers = require('./test/helpers');
const {packageJson, dir, file, dummyExecutable, buildCommand} = helpers;

helpers.skipSuiteOnWindows();

describe(`'esy build-dependencies' command`, () => {
  let prevEnv = {...process.env};

  async function getCommandEnv(p) {
    const proc = await p.esy('command-env --json');
    const env = JSON.parse(proc.stdout);
    return env;
  }

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
          linkedDep: '*',
        },
        devDependencies: {
          devDep: 'path:./devDep',
        },
        resolutions: {
          linkedDep: 'link:./linkedDep',
        },
      }),
      createPackage(p, {name: 'dep'}),
      createPackage(p, {name: 'linkedDep'}),
      createPackage(p, {name: 'devDep'}),
    );
    return p;
  }

  it(`builds dependencies`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build-dependencies');
    const env = await getCommandEnv(p);
    await expect(p.run('dep.cmd', env)).resolves.toEqual({
      stdout: '__dep__' + os.EOL,
      stderr: '',
    });
  });

  it(`doesn't build linked dependencies`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build-dependencies');
    const env = await getCommandEnv(p);
    await expect(p.run('linkedDep.cmd', env)).rejects.toMatchObject({
      code: 127,
    });
  });

  it(`builds devDependencies by default`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build-dependencies');
    const env = await getCommandEnv(p);
    await expect(p.run('devDep.cmd', env)).resolves.toMatchObject({
      stdout: '__devDep__' + os.EOL,
      stderr: '',
    });
  });

  it(`doesn't build devDependencies with --release`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build-dependencies --release');
    const env = await getCommandEnv(p);
    await expect(p.run('devDep.cmd', env)).rejects.toMatchObject({
      code: 127
    });
  });

  it(`builds linked dependencies if --all is passed`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build-dependencies --all');
    const env = await getCommandEnv(p);
    await expect(p.run('linkedDep.cmd', env)).resolves.toEqual({
      stdout: '__linkedDep__' + os.EOL,
      stderr: '',
    });
  });

  it(`builds devDependencies if --devDependencies is passed`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build-dependencies --devDependencies');
    const env = await getCommandEnv(p);
    await expect(p.run('devDep.cmd', env)).resolves.toEqual({
      stdout: '__devDep__' + os.EOL,
      stderr: '',
    });
  });
});
