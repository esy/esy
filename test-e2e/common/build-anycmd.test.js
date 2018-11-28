// @flow

const os = require('os');
const path = require('path');

const helpers = require('../test/helpers');
const {packageJson, dir, file, dummyExecutable, buildCommand} = helpers;

helpers.skipSuiteOnWindows();

describe(`'esy build CMD' invocation`, () => {
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

  it(`cannot invoke commands defined in devDependencies`, async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    await expect(p.esy('build devDep.cmd')).rejects.toMatchObject({
      code: 1,
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
