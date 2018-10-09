// @flow

const path = require('path');
const helpers = require('../test/helpers');

helpers.skipSuiteOnWindows('Needs investigation');

function makePackage(
  p,
  {
    name,
    dependencies = {},
    devDependencies = {},
  }: {
    name: string,
    dependencies?: {[name: string]: string},
    devDependencies?: {[name: string]: string},
  },
  ...items
) {
  return helpers.dir(
    name,
    helpers.packageJson({
      name: name,
      version: '1.0.0',
      license: 'MIT',
      esy: {
        buildsInSource: true,
        build: [helpers.buildCommand(p, '#{self.root / self.name}.js')],
        install: [
          `cp #{self.root / self.name}.cmd #{self.bin / self.name}.cmd`,
          `cp #{self.root / self.name}.js #{self.bin / self.name}.js`,
        ],
      },
      dependencies,
      devDependencies,
    }),
    helpers.dummyExecutable(name),
    ...items,
  );
}

function makeFixture(p) {
  return [
    helpers.packageJson({
      name: 'with-dev-dep',
      version: '1.0.0',
      esy: {
        build: 'true',
      },
      dependencies: {
        dep: 'path:./dep',
      },
      devDependencies: {
        devDep: 'path:./devDep',
      },
    }),
    makePackage(p, {
      name: 'dep',
      devDependencies: {devDepOfDep: '*'},
    }),
    makePackage(p, {
      name: 'devDep',
    }),
  ];
}

describe('devDep workflow', () => {
  async function createTestSandbox() {
    const p = await helpers.createTestSandbox();
    await p.fixture(...makeFixture(p));
    await p.esy('install');
    await p.esy('build');
    return p;
  }

  it('package "dep" should be visible in all envs', async () => {
    const p = await createTestSandbox();
    const expecting = expect.stringMatching('__dep__');

    {
      const {stdout} = await p.esy('dep.cmd');
      expect(stdout.trim()).toEqual(expecting);
    }

    {
      const {stdout} = await p.esy('b dep.cmd');
      expect(stdout.trim()).toEqual(expecting);
    }

    {
      const {stdout} = await p.esy('x dep.cmd');
      expect(stdout.trim()).toEqual(expecting);
    }
  });

  it('package "dev-dep" should be visible only in command env', async () => {
    const p = await createTestSandbox();
    const expecting = expect.stringMatching('__devDep__');

    {
      const {stdout} = await p.esy('devDep.cmd');
      expect(stdout.trim()).toEqual(expecting);
    }

    {
      const {stdout} = await p.esy('x devDep.cmd');
      expect(stdout.trim()).toEqual(expecting);
    }

    return expect(p.esy('b devDep.cmd')).rejects.toThrow();
  });
});
