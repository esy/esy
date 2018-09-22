// @flow

const path = require('path');
const helpers = require('../test/helpers');

helpers.skipSuiteOnWindows('Needs investigation');

function makePackage(
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
        build: helpers.buildCommand('#{self.root / self.name}.js'),
        install: [
          `cp #{self.root / self.name}.cmd #{self.bin / self.name}.cmd`,
          `cp #{self.root / self.name}.js #{self.bin / self.name}.js`,
        ],
      },
      dependencies,
      devDependencies,
      '_esy.source': 'path:./',
    }),
    helpers.dummyExecutable(name),
    ...items,
  );
}

const fixture = [
  helpers.packageJson({
    name: 'with-dev-dep',
    version: '1.0.0',
    esy: {
      build: 'true',
    },
    dependencies: {
      dep: '*',
    },
    devDependencies: {
      devDep: '*',
    },
  }),
  helpers.dir(
    'node_modules',
    makePackage({
      name: 'dep',
      devDependencies: {devDepOfDep: '*'},
    }),
    makePackage({
      name: 'devDep',
    }),
  ),
];

describe('devDep workflow', () => {
  let p;

  beforeEach(async () => {
    p = await helpers.createTestSandbox(...fixture);
    await p.esy('build');
  });

  it('package "dep" should be visible in all envs', async () => {
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
