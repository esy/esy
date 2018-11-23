/* @flow */

const path = require('path');
const fs = require('../test/fs.js');
const helpers = require('../test/helpers');

const {packageJson, file, dir} = helpers;

describe(`installing linked packages`, () => {
  test('it should install linked packages', async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {dep: `*`},
        resolutions: {dep: `link:./dep`},
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);

    await p.defineNpmPackage({
      name: 'depdep',
      version: '1.0.0',
      esy: {},
    });
    await p.defineNpmLocalPackage(path.join(p.projectPath, 'dep'), {
      name: 'dep',
      version: '1.0.0',
      esy: {},
      dependencies: {
        depdep: '*',
      },
    });

    await p.esy(`install`);

    expect(await helpers.readInstalledPackages(p.projectPath)).toMatchObject({
      name: 'root',
      dependencies: {
        dep: {
          name: 'dep',
          version: 'link:dep',
          dependencies: {
            depdep: {
              name: 'depdep',
              version: '1.0.0',
            },
          },
        },
      },
    });
  });

  test('it should install linked packages with bins (esy/esy#354)', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {dep: `*`},
        resolutions: {dep: `link:./dep`},
      }),
      dir(
        'dep',
        packageJson({
          name: 'dep',
          version: '1.0.0',
          bin: {
            dep: './dep.exe',
          },
        }),
        file('dep.exe', 'something'),
      ),
    ];
    const p = await helpers.createTestSandbox(...fixture);

    await p.esy(`install`);

    const layout = await helpers.readInstalledPackages(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        dep: {
          name: 'dep',
          version: 'link:dep',
        },
      },
    });

    if (helpers.isWindows) {
      await expect(p.esy('where dep')).resolves.not.toThrow();
    } else {
      await expect(p.esy('which dep')).resolves.not.toThrow();
    }
  });

  test('it should install local packages of dependencies (path: -> path:)', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {
          dep: 'path:./dep',
        },
      }),
      dir(
        'dep',
        packageJson({
          name: 'dep',
          version: '1.0.0',
          esy: {},
          dependencies: {
            linkedDep: 'path:../linkedDep',
          },
        }),
      ),
      dir(
        'linkedDep',
        packageJson({
          name: 'linkedDep',
          version: '1.0.0',
          esy: {},
        }),
      ),
    ];
    const p = await helpers.createTestSandbox(...fixture);

    await p.esy(`install`);

    const layout = await helpers.readInstalledPackages(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        dep: {
          name: 'dep',
          version: 'path:dep',
          dependencies: {
            linkedDep: {
              name: 'linkedDep',
              version: 'path:linkedDep',
            },
          },
        },
      },
    });
  });

  test('it should install local packages of dependencies (link: -> path:)', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {
          dep: '*',
        },
        resolutions: {
          dep: 'link:./dep',
        },
      }),
      dir(
        'dep',
        packageJson({
          name: 'dep',
          version: '1.0.0',
          esy: {},
          dependencies: {
            linkedDep: 'path:../linkedDep',
          },
        }),
      ),
      dir(
        'linkedDep',
        packageJson({
          name: 'linkedDep',
          version: '1.0.0',
          esy: {},
        }),
      ),
    ];
    const p = await helpers.createTestSandbox(...fixture);

    await p.esy(`install`);

    const layout = await helpers.readInstalledPackages(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        dep: {
          name: 'dep',
          version: 'link:dep',
          dependencies: {
            linkedDep: {
              name: 'linkedDep',
              version: 'path:linkedDep',
            },
          },
        },
      },
    });
  });

  test('link to ancestor directories', async () => {
    const fixture = [
      packageJson({
        name: 'dep',
        version: '1.0.0',
        esy: {},
        dependencies: {},
      }),
      dir(
        'sub',
        dir(
          'dir',
          packageJson({
            name: 'root',
            version: '1.0.0',
            esy: {},
            dependencies: {
              dep: '*',
            },
            resolutions: {
              dep: 'link:../../',
            },
          }),
        ),
      ),
    ];
    const p = await helpers.createTestSandbox(...fixture);

    p.cd('./sub/dir');
    await p.esy(`install`);

    const layout = await helpers.readInstalledPackages(
      path.join(p.projectPath, 'sub', 'dir'),
    );
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        dep: {
          name: 'dep',
          version: `link:../..`,
        },
      },
    });
  });

  it('should re-install if linked package dependencies were changed', async () => {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {dep: '*'},
        resolutions: {dep: 'link:dep'},
        esy: {},
      }),
      helpers.dir(
        'dep',
        helpers.packageJson({
          name: 'dep',
          version: '1.0.0',
          dependencies: {depdep: '1.0.0'},
          esy: {},
        }),
      ),
    );

    await p.defineNpmPackage({
      name: 'depdep',
      version: '1.0.0',
      esy: {},
    });

    await p.defineNpmPackage({
      name: 'depdep',
      version: '2.0.0',
      esy: {},
    });

    await p.esy('install');

    expect(await helpers.readInstalledPackages(p.projectPath)).toMatchObject({
      name: 'root',
      dependencies: {
        dep: {
          name: 'dep',
          dependencies: {
            depdep: {
              name: 'depdep',
              version: '1.0.0',
            },
          },
        },
      },
    });

    // now change root package.json

    await fs.writeFile(
      path.join(p.projectPath, 'dep', 'package.json'),
      JSON.stringify(
        {
          name: 'dep',
          version: '1.0.0',
          dependencies: {depdep: '2.0.0'},
          esy: {},
        },
        null,
        2,
      ),
    );

    // make sure if we run `esy install` it will re-install packages

    await p.esy('install');

    expect(await helpers.readInstalledPackages(p.projectPath)).toMatchObject({
      name: 'root',
      dependencies: {
        dep: {
          name: 'dep',
          dependencies: {
            depdep: {
              name: 'depdep',
              version: '2.0.0',
            },
          },
        },
      },
    });
  });
});
