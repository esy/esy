// @flow

const path = require('path');
const helpers = require('../test/helpers');

function makePackage(
  {
    name,
    dependencies = {},
    devDependencies = {},
    optDependencies = {},
    exportedEnv = {},
  }: {
    name: string,
    dependencies?: {[name: string]: string},
    devDependencies?: {[name: string]: string},
    optDependencies?: {[name: string]: string},
    exportedEnv?: {[name: string]: {val: string}},
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
        build: 'chmod +x #{self.name}.exe',
        install: 'cp #{self.name}.exe #{self.bin / self.name}.exe',
        exportedEnv,
      },
      dependencies,
      optDependencies,
      devDependencies,
      '_esy.source': 'path:.',
    }),
    helpers.dummyExecutable(name),
    ...items,
  );
}

const fixture = [
  helpers.packageJson({
    name: 'withDep',
    version: '1.0.0',
    esy: {
      build: 'true',
    },
    dependencies: {
      dep: '*',
      focus: '*',
    },
  }),
  helpers.dir(
    'node_modules',
    makePackage({
      name: 'dep',
      dependencies: {
        focus: '*',
        depOfDep: '*',
      },
    }),
    makePackage({
      name: 'depOfDep',
      dependencies: {
        focus: '*',
      },
    }),
    makePackage({
      name: 'focus',
      exportedEnv: {direct__val: {val: '__focus__', scope: 'local'}},
    }),
  ),
];

describe('dep exists as transitive and direct dep at once', () => {
  it('package focus should be visible in all envs', async () => {
    const p = await helpers.createTestSandbox(...fixture);
    await p.esy('build');

    {
      const {stdout} = await p.esy('focus.exe');
      expect(stdout.trim()).toEqual('__focus__');
    }

    {
      const {stdout} = await p.esy('b focus.exe');
      expect(stdout.trim()).toEqual('__focus__');
    }

    {
      const {stdout} = await p.esy('x focus.exe');
      expect(stdout.trim()).toEqual('__focus__');
    }
  });

  it('package focus local exports should be available', async () => {
    const p = await helpers.createTestSandbox(...fixture);
    const env = JSON.parse((await p.esy('build-env --json')).stdout);
    expect(env.direct__val).toBe('__focus__');
  });
});
