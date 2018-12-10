// @flow
//
// This tests monorepo workflow.
//
// The project structure is the following:
//
//   root -depends-> pkga, pkgb, pkgc
//   pkgb -depends-> pkgc
//   root -devDepends-> devDep
//
// Also pkga, pkgb and pkgc are configured to use devDep.cmd executable from
// devDep when built in dev mode ("esy.buildDev" config).
//
// The idea is that we need to use a special config to add devDep to pkg* build
// environments.
//

const helpers = require('../test/helpers.js');
const {packageJson, dir, dummyExecutable} = helpers;

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
            'devDep.cmd',
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
      devDependencies: {
        devDep: 'path:./devDep',
      },
      resolutions: {
        pkga: 'link:./pkga',
        pkgb: 'link:./pkgb',
        pkgc: 'link:./pkgc',
      },
    }),
    dir(
      'pkga',
      ...createPackage({
        name: 'pkga',
        dependencies: {},
        devDependencies: {},
        resolutions: {},
      }),
    ),
    dir(
      'pkgb',
      ...createPackage({
        name: 'pkgb',
        dependencies: {pkgc: '*'},
        devDependencies: {},
        resolutions: {},
      }),
    ),
    dir(
      'pkgc',
      ...createPackage({
        name: 'pkgc',
        dependencies: {},
        devDependencies: {},
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
  const depspec = 'dependencies(self)+devDependencies(root)';

  test('that the build is failing with default config', async function() {
    const p = await createTestSandbox();

    // simple build doesn't work as we are using devDep of the root in "buildDev"
    await expect(p.esy('build')).rejects.toThrowError(
      'unable to resolve command: devDep.cmd',
    );

    await expect(p.esy('build-dependencies --all')).rejects.toThrowError(
      'unable to resolve command: devDep.cmd',
    );
  });

  test.only('that the build is ok with custom DEPSPEC config', async function() {
    // now try to build with a custom DEPSPEC
    const p = await createTestSandbox();

    await p.esy(`build-dependencies --all --link-depspec "${depspec}"`);

    for (const pkg of ['pkga', 'pkgb', 'pkgc']) {
      const {stdout} = await p.esy(
        `exec-command --include-current-env --link-depspec "${depspec}" root -- ${pkg}.cmd`,
      );
      expect(stdout.trim()).toBe(`__${pkg}__`);
    }
  });

  test('that the release build is ok with custom DEPSPEC config', async function() {
    // release build should work as-is as we are building using `"esy.build"`
    // commands.
    const p = await createTestSandbox();
    await p.esy('build-dependencies --all --release');

    for (const pkg of ['pkga', 'pkgb', 'pkgc']) {
      const {stdout} = await p.esy(
        `exec-command --release --include-current-env root -- ${pkg}.cmd`,
      );
      expect(stdout.trim()).toBe(`__${pkg}__`);
    }
  });

  test('running command in monorepo package env (referring to a package by name)', async function() {
    // run commands in a specified package environment.
    const p = await createTestSandbox();
    const {stdout} = await p.esy(
      `exec-command --link-depspec "${depspec}" pkga -- echo '#{self.name}'`,
    );

    expect(stdout.trim()).toBe('pkga');
  });

  test('running command in monorepo package env (referring to a package by path)', async function() {
    // we can also refer to linked package by its manifest path
    const p = await createTestSandbox();
    const {stdout} = await p.esy(
      `exec-command --link-depspec "${depspec}" ./pkgb/package.json -- echo '#{self.name}'`,
    );

    expect(stdout.trim()).toBe('pkgb');
  });
});
