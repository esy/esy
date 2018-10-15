/* @flow */

const helpers = require('../test/helpers.js');

describe('Installing devDependencies', function() {
  test(`it should install devDependencies`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        devDependencies: {devDep: `1.0.0`},
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.defineNpmPackage({
      name: 'devDep',
      version: '1.0.0',
      esy: {},
      dependencies: {},
    });

    await p.esy(`install`);

    await expect(helpers.readInstalledPackages(p.projectPath)).resolves.toMatchObject({
      dependencies: {
        devDep: {
          name: 'devDep',
        },
      },
    });
  });

  test(`it should install devDependencies along with its deps`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        devDependencies: {devDep: `1.0.0`},
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.defineNpmPackage({
      name: 'devDep',
      version: '1.0.0',
      esy: {},
      dependencies: {
        ok: '1.0.0',
      },
    });
    await p.defineNpmPackage({
      name: 'ok',
      version: '1.0.0',
      esy: {},
      dependencies: {},
    });

    await p.esy(`install`);

    await expect(helpers.readInstalledPackages(p.projectPath)).resolves.toMatchObject({
      dependencies: {
        ok: {
          name: 'ok',
          version: '1.0.0',
        },
        devDep: {
          name: 'devDep',
          dependencies: {},
        },
      },
    });
  });

  test(`it should prefer an already installed version when solving devDeps deps`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {ok: `1.0.0`},
        esy: {},
        devDependencies: {devDep: `1.0.0`},
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);

    await p.defineNpmPackage({
      name: 'devDep',
      version: '1.0.0',
      esy: {},
      dependencies: {
        ok: '*',
      },
    });
    await p.defineNpmPackage({
      name: 'ok',
      version: '1.0.0',
      esy: {},
      dependencies: {},
    });
    await p.defineNpmPackage({
      name: 'ok',
      version: '2.0.0',
      esy: {},
      dependencies: {},
    });

    await p.esy(`install`);

    const layout = await helpers.readInstalledPackages(p.projectPath);
    await expect(layout).toMatchObject({
      dependencies: {
        ok: {
          name: 'ok',
          version: '1.0.0',
        },
        devDep: {
          name: 'devDep',
          dependencies: {},
        },
      },
    });
    expect(layout).not.toHaveProperty('dependencies.devDep.dependencies.ok');
  });

  test(`it should handle two devDeps sharing a dep`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        devDependencies: {devDep: `1.0.0`, devDep2: '1.0.0'},
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);

    await p.defineNpmPackage({
      name: 'devDep',
      version: '1.0.0',
      esy: {},
      dependencies: {
        ok: '*',
      },
    });
    await p.defineNpmPackage({
      name: 'devDep2',
      version: '1.0.0',
      esy: {},
      dependencies: {
        ok: '*',
      },
    });
    await p.defineNpmPackage({
      name: 'ok',
      version: '1.0.0',
      esy: {},
      dependencies: {},
    });

    await p.esy(`install`);

    const layout = await helpers.readInstalledPackages(p.projectPath);
    await expect(layout).toMatchObject({
      dependencies: {
        ok: {
          name: 'ok',
        },
        devDep: {
          name: 'devDep',
          dependencies: {},
        },
        devDep2: {
          name: 'devDep2',
          dependencies: {},
        },
      },
    });
  });
});
