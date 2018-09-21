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
        build: 'chmod +x #{self.root / self.name}.exe',
        install: [`cp #{self.root / self.name}.exe #{self.bin / self.name}.exe`],
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
      const {stdout} = await p.esy('dep.exe');
      expect(stdout.trim()).toEqual(expecting);
    }

    {
      const {stdout} = await p.esy('b dep.exe');
      expect(stdout.trim()).toEqual(expecting);
    }

    {
      const {stdout} = await p.esy('x dep.exe');
      expect(stdout.trim()).toEqual(expecting);
    }
  });

  it('package "dev-dep" should be visible only in command env', async () => {
    const expecting = expect.stringMatching('__devDep__');

    {
      const {stdout} = await p.esy('devDep.exe');
      expect(stdout.trim()).toEqual(expecting);
    }

    {
      const {stdout} = await p.esy('x devDep.exe');
      expect(stdout.trim()).toEqual(expecting);
    }

    return expect(p.esy('b devDep.exe')).rejects.toThrow();
  });
});
