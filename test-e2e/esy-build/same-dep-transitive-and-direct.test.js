// @flow

const path = require('path');
const helpers = require('../test/helpers');

function makePackage(
  p,
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
        build: [helpers.buildCommand(p, '#{self.name}.js')],
        install: [
          'cp #{self.name}.cmd #{self.bin / self.name}.cmd',
          'cp #{self.name}.js #{self.bin / self.name}.js',
        ],
        exportedEnv,
      },
      dependencies,
      optDependencies,
      devDependencies,
    }),
    helpers.dummyExecutable(name),
    ...items,
  );
}

async function createTestSandbox() {
  const p = await helpers.createTestSandbox();
  await p.fixture(
    helpers.packageJson({
      name: 'withDep',
      version: '1.0.0',
      esy: {
        build: 'true',
      },
      dependencies: {
        dep: 'path:./dep',
        focus: 'path:./focus',
      },
    }),
    makePackage(p, {
      name: 'dep',
      dependencies: {
        focus: 'path:../focus',
        depOfDep: 'path:../depOfDep',
      },
    }),
    makePackage(p, {
      name: 'depOfDep',
      dependencies: {
        focus: 'path:../focus',
      },
    }),
    makePackage(p, {
      name: 'focus',
      exportedEnv: {direct__val: {val: '__focus__', scope: 'local'}},
    }),
  );
  return p;
}

describe('dep exists as transitive and direct dep at once', () => {
  it('package focus should be visible in all envs', async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    await p.esy('build');

    {
      const {stdout} = await p.esy('focus.cmd');
      expect(stdout.trim()).toEqual('__focus__');
    }

    {
      const {stdout} = await p.esy('b focus.cmd');
      expect(stdout.trim()).toEqual('__focus__');
    }

    {
      const {stdout} = await p.esy('x focus.cmd');
      expect(stdout.trim()).toEqual('__focus__');
    }
  });

  it('package focus local exports should be available', async () => {
    const p = await createTestSandbox();
    await p.esy('install');
    const env = JSON.parse((await p.esy('build-env --json')).stdout);
    expect(env.direct__val).toBe('__focus__');
  });
});
