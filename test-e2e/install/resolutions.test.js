/* @flow */

const helpers = require('../test/helpers.js');

helpers.skipSuiteOnWindows();

describe(`Installing with resolutions`, () => {
  test(`it should prefer resolution over dependencies for the root`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {dep: `1.0.0`},
        resolutions: {dep: `2.0.0`},
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.defineNpmPackage({
      name: 'dep',
      version: '1.0.0',
      esy: {},
    });
    await p.defineNpmPackage({
      name: 'dep',
      version: '2.0.0',
      esy: {},
    });

    await p.esy(`install`);

    const layout = await helpers.crawlLayout(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        dep: {
          name: 'dep',
          version: '2.0.0',
        },
      },
    });
  });

  test(`it should prefer resolution over dependencies for the dependency`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {dep: `1.0.0`},
        resolutions: {depDep: `2.0.0`},
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.defineNpmPackage({
      name: 'dep',
      version: '1.0.0',
      esy: {},
      dependencies: {depDep: `1.0.0`},
    });
    await p.defineNpmPackage({
      name: 'depDep',
      esy: {},
      version: '1.0.0',
    });
    await p.defineNpmPackage({
      name: 'depDep',
      esy: {},
      version: '2.0.0',
    });

    await p.esy(`install`);

    const layout = await helpers.crawlLayout(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        dep: {
          name: 'dep',
          version: '1.0.0',
        },
        depDep: {
          name: 'depDep',
          version: '2.0.0',
        },
      },
    });
  });

  test(`it should find resolutions for non-esy npm packages`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {dep: `1.0.0`},
        resolutions: {depDep: `2.0.0`},
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.defineNpmPackage({
      name: 'dep',
      version: '1.0.0',
      dependencies: {depDep: `1.0.0`},
    });
    await p.defineNpmPackage({
      name: 'depDep',
      version: '1.0.0',
    });
    await p.defineNpmPackage({
      name: 'depDep',
      version: '2.0.0',
    });

    await p.esy(`install`);

    const layout = await helpers.crawlLayout(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        dep: {
          name: 'dep',
          version: '1.0.0',
        },
        depDep: {
          name: 'depDep',
          version: '2.0.0',
        },
      },
    });
  });

  test(`resolutions could be a linked package`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {dep: `1.0.0`},
        resolutions: {dep: `link:./dep`},
      }),
      helpers.dir(
        'dep',
        helpers.packageJson({
          name: 'dep',
          version: '2.0.0',
          esy: {},
        }),
      ),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.defineNpmPackage({
      name: 'dep',
      version: '1.0.0',
      esy: {},
    });

    await p.esy(`install`);

    const layout = await helpers.crawlLayout(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        dep: {
          name: 'dep',
          version: '2.0.0',
        },
      },
    });
  });

  test.only(`resolutions could be a linked package (@opam case)`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {'@opam/dep': `1.0.0`},
        resolutions: {'@opam/dep': `link:./dep`},
      }),
      helpers.dir(
        'dep',
        helpers.packageJson({
          name: '@opam/dep',
          version: '2.0.0',
          esy: {},
        }),
      ),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.defineOpamPackage({
      name: 'dep',
      version: '1.0.0',
      opam: `
        opam-version: 1.2
      `,
      url: null,
    });

    await p.esy(`install`);

    const layout = await helpers.crawlLayout(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        '@opam/dep': {
          name: '@opam/dep',
          version: '2.0.0',
        },
      },
    });
  });
});
