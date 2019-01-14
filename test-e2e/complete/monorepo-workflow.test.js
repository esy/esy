// @flow
//
// This tests monorepo workflow.
//
// The project structure is the following:
//
//   root -links-dev-> pkga, pkgb, pkgc
//   pkgb -links-dev-> pkgc
//   root -devDepends-> devDep
//
// Also pkga, pkgb and pkgc are configured to use devDep.cmd executable from
// devDep when built in dev mode ("esy.buildDev" config).
//
// The idea is that we need to use a special config to add devDep to pkg* build
// environments.
//

const helpers = require('../test/helpers.js');
const {test, isWindows, packageJson, file, dir, dummyExecutable} = helpers;

async function createTestSandbox() {
  const p = await helpers.createTestSandbox();

  const devDep = [
    packageJson({
      name: 'devDep',
      version: '1.0.0',
      esy: {
        buildsInSource: true,
        build: [helpers.buildCommand(p, '#{self.root / self.name}.js')],
        install: [
          `cp #{self.root / self.name}.cmd #{self.bin / self.name}.cmd`,
          `cp #{self.root / self.name}.js #{self.bin / self.name}.js`,
        ],
      },
    }),
    dummyExecutable('devDep'),
  ];

  function createPackage({name, dependencies, devDependencies, resolutions}) {
    devDependencies = devDependencies || {};
    return [
      packageJson({
        name,
        version: '1.0.0',
        esy: {
          build: [
            'cp #{self.root / self.name}.js #{self.target_dir / self.name}.js',
            helpers.buildCommand(p, '#{self.target_dir / self.name}.js'),
          ],
          buildDev: [
            devDependencies.devDep != null ? 'devDep.cmd' : 'true',
            'cp #{self.root / self.name}.js #{self.target_dir / self.name}.js',
            helpers.buildCommand(p, '#{self.target_dir / self.name}.js'),
          ],
          install: [
            `cp #{self.target_dir / self.name}.cmd #{self.bin / self.name}.cmd`,
            `cp #{self.target_dir / self.name}.js #{self.bin / self.name}.js`,
          ],
        },
        dependencies,
        devDependencies,
        resolutions,
      }),
      dummyExecutable(name),
    ];
  }

  const fixture = [
    ...createPackage({
      name: 'root',
      dependencies: {
        pkga: '*',
        pkgb: '*',
        pkgc: '*',
      },
      resolutions: {
        pkga: 'link-dev:./pkga',
        pkgb: 'link-dev:./pkgb',
        pkgc: 'link-dev:./pkgc',
      },
    }),
    file('.esyproject', ''),
    dir(
      'pkga',
      ...createPackage({
        name: 'pkga',
        dependencies: {},
        devDependencies: {
          devDep: 'path:../devDep',
        },
        resolutions: {},
      }),
    ),
    dir(
      'pkgb',
      ...createPackage({
        name: 'pkgb',
        dependencies: {pkgc: '*'},
        devDependencies: {
          devDep: 'path:../devDep',
        },
        resolutions: {},
      }),
    ),
    dir(
      'pkgc',
      ...createPackage({
        name: 'pkgc',
        dependencies: {},
        devDependencies: {
          devDep: 'path:../devDep',
        },
        resolutions: {},
      }),
    ),
    dir('devDep', ...devDep),
  ];
  await p.fixture(...fixture);
  await p.esy('install');
  return p;
}

describe('Monorepo workflow using low level commands', function() {

  test('building the monorepo', async function() {
    // now try to build with a custom DEPSPEC
    const p = await createTestSandbox();

    await p.esy(`build`);

    for (const pkg of ['pkga', 'pkgb', 'pkgc']) {
      const {stdout} = await p.esy(
        `exec-command --include-current-env ${pkg}.cmd`,
      );
      expect(stdout.trim()).toBe(`__${pkg}__`);
    }
  });

  test('building the monorepo in release mode', async function() {
    // release build should work as-is as we are building using `"esy.build"`
    // commands.
    const p = await createTestSandbox();
    await p.esy('build --release');

    for (const pkg of ['pkga', 'pkgb', 'pkgc']) {
      const {stdout} = await p.esy(
        `exec-command --release --include-current-env ${pkg}.cmd`,
      );
      expect(stdout.trim()).toBe(`__${pkg}__`);
    }
  });

  test.disableIf(isWindows)(
    'running command in monorepo package env (referring to a package by name)',
    async function() {
      // run commands in a specified package environment.
      const p = await createTestSandbox();
      const {stdout} = await p.esy(`-p pkga echo '#{self.name}'`);

      expect(stdout.trim()).toBe('pkga');
    },
  );

  test.disableIf(isWindows)(
    'running command in monorepo package env (referring to a package by changing cwd)',
    async function() {
      // run commands in a specified package environment.
      const p = await createTestSandbox();
      p.cd('./pkga');
      const {stdout} = await p.esy(`echo '#{self.name}'`);
      p.cd('../');

      expect(stdout.trim()).toBe('pkga');
    },
  );

  test.disableIf(isWindows)(
    'running command in monorepo package env (referring to a package by path)',
    async function() {
      // we can also refer to linked package by its manifest path
      const p = await createTestSandbox();
      const {stdout} = await p.esy(`-p ./pkgb/package.json echo '#{self.name}'`);

      expect(stdout.trim()).toBe('pkgb');
    },
  );
});
