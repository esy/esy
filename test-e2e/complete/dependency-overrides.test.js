// @flow

const helpers = require('../test/helpers.js');
const {file, dir, packageJson, dummyExecutable} = helpers;

helpers.skipSuiteOnWindows("esy-solve-cudf isn't ready");

describe('dependency overrides', function() {
  it('allow to place override in a dependency (override dependencies)', async function() {
    const p = await helpers.createTestSandbox();

    await p.defineNpmPackage({
      name: 'depdep',
      version: '1.0.0',
    });

    await p.defineNpmPackage({
      name: 'depdep',
      version: '2.0.0',
    });

    await p.fixture(
      packageJson({
        name: 'root',
        dependencies: {
          dep: 'path:./dep-override',
        },
      }),
      dir(
        'dep-override',
        packageJson({
          source: 'path:../dep',
          override: {
            dependencies: {
              depdep: '1.0.0',
            },
          },
        }),
      ),
      dir(
        'dep',
        packageJson({
          name: 'dep',
          dependencies: {
            depdep: '2.0.0',
          },
        }),
      ),
    );

    await p.esy('install --skip-repository-update');

    expect(await helpers.readInstalledPackages(p.projectPath)).toMatchObject({
      dependencies: {
        dep: {
          name: 'dep',
          dependencies: {
            depdep: {name: 'depdep', version: '1.0.0'},
          },
        },
      },
    });
  });

  it('allow to place override in a dependency (override dependencies + link)', async function() {
    const p = await helpers.createTestSandbox();

    await p.defineNpmPackage({
      name: 'depdep',
      version: '1.0.0',
    });

    await p.defineNpmPackage({
      name: 'depdep',
      version: '2.0.0',
    });

    await p.fixture(
      packageJson({
        name: 'root',
        dependencies: {
          dep: 'link:./dep-override',
        },
      }),
      dir(
        'dep-override',
        packageJson({
          source: 'path:../dep',
          override: {
            dependencies: {
              depdep: '1.0.0',
            },
          },
        }),
      ),
      dir(
        'dep',
        packageJson({
          name: 'dep',
          dependencies: {
            depdep: '2.0.0',
          },
        }),
      ),
    );

    await p.esy('install --skip-repository-update');

    expect(await helpers.readInstalledPackages(p.projectPath)).toMatchObject({
      dependencies: {
        dep: {
          name: 'dep',
          dependencies: {
            depdep: {name: 'depdep', version: '1.0.0'},
          },
        },
      },
    });
  });

  it('allow to place override in a dependency (override a source with no manifest)', async function() {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          dep: 'path:./dep-port',
        },
      }),
      dir(
        'dep-port',
        packageJson({
          source: 'path:../dep-orig',
          override: {
            buildsInSource: true,
            build: [helpers.buildCommand(p, 'hello.js')],
            install: 'cp hello.js hello.cmd #{self.bin}/',
          },
        }),
      ),
      dir('dep-orig', dummyExecutable('hello')),
    );

    await p.esy('install');
    await p.esy('build');

    const {stdout} = await p.esy('hello.cmd');
    expect(stdout.trim()).toEqual('__hello__');
  });
});
