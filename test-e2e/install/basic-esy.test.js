/* @flow */

const helpers = require('../test/helpers.js');
const path = require('path');
const fs = require('../test/fs.js');

describe(`Basic tests`, () => {
  test(`it should correctly install a single dependency that contains no sub-dependencies`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {[`no-deps`]: `1.0.0`},
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);

    await p.esy(`install`);

    expect(await fs.exists(path.join(p.projectPath, 'esy.lock'))).toBeTruthy();

    await expect(
      p.runJavaScriptInNodeAndReturnJson(`require('no-deps')`),
    ).resolves.toMatchObject({
      name: `no-deps`,
      version: `1.0.0`,
    });
  });

  test(`it should correctly install a dependency that itself contains a fixed dependency`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {[`one-fixed-dep`]: `1.0.0`},
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.esy(`install`);

    await expect(
      p.runJavaScriptInNodeAndReturnJson(`require('one-fixed-dep')`),
    ).resolves.toMatchObject({
      name: `one-fixed-dep`,
      version: `1.0.0`,
      dependencies: {
        [`no-deps`]: {
          name: `no-deps`,
          version: `1.0.0`,
        },
      },
    });
  });

  test(`it should correctly install a dependency that itself contains a range dependency`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {[`one-range-dep`]: `1.0.0`},
      }),
    ];

    const p = await helpers.createTestSandbox(...fixture);
    await p.esy(`install`);

    await expect(
      p.runJavaScriptInNodeAndReturnJson(`require('one-range-dep')`),
    ).resolves.toMatchObject({
      name: `one-range-dep`,
      version: `1.0.0`,
      dependencies: {
        [`no-deps`]: {
          name: `no-deps`,
          version: `1.1.0`,
        },
      },
    });
  });

  test(`it should prefer esy._dependenciesForNewEsyInstaller`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {apkg: `1.0.0`},
        esy: {},
      }),
    ];

    const p = await helpers.createTestSandbox(...fixture);
    await p.defineNpmPackage({
      name: 'apkg',
      version: '1.0.0',
      esy: {
        _dependenciesForNewEsyInstaller: {
          'apkg-dep': `2.0.0`,
        },
      },
      dependencies: {'apkg-dep': `1.0.0`},
    });
    await p.defineNpmPackage({
      name: 'apkg-dep',
      esy: {},
      version: '1.0.0',
    });
    await p.defineNpmPackage({
      name: 'apkg-dep',
      esy: {},
      version: '2.0.0',
    });

    await p.esy(`install`);

    await expect(helpers.readInstalledPackages(p.projectPath)).resolves.toMatchObject({
      dependencies: {
        apkg: {
          name: 'apkg',
          version: `1.0.0`,
          dependencies: {
            'apkg-dep': {
              name: 'apkg-dep',
              version: `2.0.0`,
            },
          },
        },
      },
    });
  });

  test(`it should correctly install a dependency by a dist-tag (latest)`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {tagged: `latest`},
      }),
    ];

    const p = await helpers.createTestSandbox(...fixture);

    await p.defineNpmPackage({
      name: 'tagged',
      version: '1.0.0',
      esy: {},
    });

    await p.defineNpmPackage({
      name: 'tagged',
      version: '2.0.0',
      esy: {},
    });

    await p.esy('install');

    const layout = await helpers.readInstalledPackages(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        tagged: {
          name: 'tagged',
          version: '2.0.0',
        },
      },
    });
  });

  test(`it should correctly install a dependency by a dist-tag (legacy)`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {tagged: `legacy`},
      }),
    ];

    const p = await helpers.createTestSandbox(...fixture);

    await p.defineNpmPackage(
      {
        name: 'tagged',
        version: '1.0.0',
        esy: {},
      },
      {distTag: 'legacy'},
    );

    await p.defineNpmPackage({
      name: 'tagged',
      version: '2.0.0',
      esy: {},
    });

    await p.esy('install');

    const layout = await helpers.readInstalledPackages(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        tagged: {
          name: 'tagged',
          version: '1.0.0',
        },
      },
    });
  });

  test(`it should correctly install a dependency by a dist-tag (latest, prereleases present)`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {tagged: `latest`},
        esy: {},
      }),
    ];

    const p = await helpers.createTestSandbox(...fixture);

    await p.defineNpmPackage({
      name: 'tagged',
      version: '1.0.0',
      esy: {},
    });

    await p.defineNpmPackage({
      name: 'tagged',
      version: '2.0.0',
      esy: {},
    });

    await p.defineNpmPackage({
      name: 'tagged',
      version: '3.0.0-alpha',
      esy: {},
    });

    await p.esy('install');

    const layout = await helpers.readInstalledPackages(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        tagged: {
          name: 'tagged',
          version: '2.0.0',
        },
      },
    });
  });

  test(`it should correctly install a dependency by a dist-tag (next)`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {tagged: `next`},
        esy: {},
      }),
    ];

    const p = await helpers.createTestSandbox(...fixture);

    await p.defineNpmPackage({
      name: 'tagged',
      version: '1.0.0',
      esy: {},
    });

    await p.defineNpmPackage({
      name: 'tagged',
      version: '2.0.0',
      esy: {},
    });

    await p.defineNpmPackage(
      {
        name: 'tagged',
        version: '3.0.0',
        esy: {},
      },
      {distTag: 'next'},
    );

    await p.esy('install');

    const layout = await helpers.readInstalledPackages(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        tagged: {
          name: 'tagged',
          version: '3.0.0',
        },
      },
    });
  });

  it('should re-install if package dependencies were changed', async () => {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {dep: `1.0.0`},
        esy: {},
      }),
    );

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

    await p.esy('install');

    expect(await helpers.readInstalledPackages(p.projectPath)).toMatchObject({
      name: 'root',
      dependencies: {
        dep: {
          name: 'dep',
          version: '1.0.0',
        },
      },
    });

    // now change root package.json

    await fs.writeFile(
      path.join(p.projectPath, 'package.json'),
      JSON.stringify(
        {
          name: 'root',
          version: '1.0.0',
          dependencies: {dep: `2.0.0`},
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
          version: '2.0.0',
        },
      },
    });
  });
});
