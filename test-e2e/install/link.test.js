/* @flow */

const path = require('path');
const helpers = require('../test/helpers');

const {packageJson, file, dir} = helpers;

describe(`installing linked packages`, () => {
  test('it should install linked packages', async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {dep: `link:./dep`},
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

    const layout = await helpers.crawlLayout(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        depdep: {
          name: 'depdep',
          version: '1.0.0',
        },
        dep: {
          name: 'dep',
          version: '1.0.0',
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
        dependencies: {dep: `link:./dep`},
      }),
      dir(
        'dep',
        packageJson({
          name: 'dep',
          version: '1.0.0',
          esy: {},
          bin: {
            dep: './dep.exe',
          },
        }),
        file('dep.exe', 'something'),
      ),
    ];
    const p = await helpers.createTestSandbox(...fixture);

    await p.esy(`install`);

    const layout = await helpers.crawlLayout(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        dep: {
          name: 'dep',
          version: '1.0.0',
        },
      },
    });

    const binPath = path.join(p.projectPath, 'node_modules', '.bin', 'dep');
    expect(await helpers.exists(binPath)).toBeTruthy();
    const binContents = await helpers.readFile(binPath);
    expect(binContents.toString()).toEqual('something');
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

    const layout = await helpers.crawlLayout(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        dep: {
          name: 'dep',
          version: '1.0.0',
        },
        linkedDep: {
          name: 'linkedDep',
          version: '1.0.0',
        },
      },
    });
  });

  test('it should install local packages of dependencies (path: -> link:)', async () => {
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
            linkedDep: 'link:../linkedDep',
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

    const layout = await helpers.crawlLayout(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        dep: {
          name: 'dep',
          version: '1.0.0',
        },
        linkedDep: {
          name: 'linkedDep',
          version: '1.0.0',
        },
      },
    });
  });

  test('it should install local packages of dependencies (link: -> link:)', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {
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
            linkedDep: 'link:../linkedDep',
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

    const layout = await helpers.crawlLayout(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        dep: {
          name: 'dep',
          version: '1.0.0',
        },
        linkedDep: {
          name: 'linkedDep',
          version: '1.0.0',
        },
      },
    });
  });
});
