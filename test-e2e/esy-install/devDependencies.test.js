/* @flow */

const helpers = require('../test/helpers.js');

async function requireJson(p, req) {
  const {stdout} = await p.esy(`node -p "JSON.stringify(require('${req}'))"`);
  return JSON.parse(stdout);
}

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
    await p.esy(`build`);

    expect(await requireJson(p, 'devDep/package.json')).toMatchObject({
      name: 'devDep',
      version: '1.0.0',
    });

    await expect(helpers.readInstalledPackages(p.projectPath)).resolves.toMatchObject({
      devDependencies: {
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
    await p.esy(`build`);

    expect(await requireJson(p, 'devDep/package.json')).toMatchObject({
      name: 'devDep',
      version: '1.0.0',
    });

    await expect(helpers.readInstalledPackages(p.projectPath)).resolves.toMatchObject({
      devDependencies: {
        devDep: {
          name: 'devDep',
          dependencies: {
            ok: {
              name: 'ok',
              version: '1.0.0',
            },
          },
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
      },
      devDependencies: {
        devDep: {
          name: 'devDep',
          dependencies: {
            ok: {
              name: 'ok',
              version: '1.0.0',
            },
          },
        },
      },
    });
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
      devDependencies: {
        devDep: {
          name: 'devDep',
          dependencies: {
            ok: {
              name: 'ok',
            },
          },
        },
        devDep2: {
          name: 'devDep2',
          dependencies: {
            ok: {
              name: 'ok',
            },
          },
        },
      },
    });
  });
});
