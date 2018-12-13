/* @flow */

const helpers = require('../test/helpers.js');

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

    const layout = await helpers.readInstalledPackages(p.projectPath);
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

    const layout = await helpers.readInstalledPackages(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        dep: {
          name: 'dep',
          version: '1.0.0',
          dependencies: {
            depDep: {
              name: 'depDep',
              version: '2.0.0',
            },
          },
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

    const layout = await helpers.readInstalledPackages(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        dep: {
          name: 'dep',
          version: '1.0.0',
          dependencies: {
            depDep: {
              name: 'depDep',
              version: '2.0.0',
            },
          },
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
  });

  test(`resolutions could be a linked package (@opam case)`, async () => {
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

    const layout = await helpers.readInstalledPackages(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        '@opam/dep': {
          name: '@opam/dep',
          version: 'link:dep',
        },
      },
    });
  });

  test(`resolutions could have local packages`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {dep: '1.0.0'},
        resolutions: {dep: 'link:./dep'},
      }),
      helpers.dir(
        'dep',
        helpers.packageJson({
          name: 'dep',
          version: '1.0.0',
          esy: {},
          dependencies: {
            // this path should be resolved against this location
            depdep: 'path:../depdep',
          },
        }),
      ),
      helpers.dir(
        'depdep',
        helpers.packageJson({
          name: 'depdep',
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
            depdep: {
              name: 'depdep',
              version: 'path:depdep',
            },
          },
        },
      },
    });
  });

  test(`resolutions overrides could inject linked packages`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {dep: '1.0.0'},
        resolutions: {
          dep: {
            source: 'path:./dep',
            override: {
              dependencies: {
                // this path should be resolved against this location
                depdep: 'path:./depdep',
              },
            },
          },
        },
      }),
      helpers.dir(
        'dep',
        helpers.packageJson({
          name: 'dep',
          version: '1.0.0',
          esy: {},
        }),
      ),
      helpers.dir(
        'depdep',
        helpers.packageJson({
          name: 'depdep',
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
            depdep: {
              name: 'depdep',
              version: 'path:depdep',
            },
          },
        },
      },
    });
  });

  test(`should display a warning in case of unused resolutions during install`, async () => {
    const p = await helpers.createTestSandbox();

    await p.defineNpmPackage({
      name: 'dep',
      version: `2.0.0`,
    });

    await p.fixture(
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {dep: `1.0.0`},
        resolutions: {dep: `2.0.0`, unused: `1.0.0`},
      }),
    );

    const result = await p.esy(`install`);

    expect(
      result.stderr.includes(
        'warn resolution "unused" is unused (defined in package.json)',
      ),
    ).toBe(true);
    expect(
      result.stderr.includes('warn resolution "dep" is unused (defined in package.json)'),
    ).toBe(false);
  });

  test(`should display a warning in case of unused resolutions during add`, async () => {
    const p = await helpers.createTestSandbox();

    await p.defineNpmPackage({
      name: 'dep',
      version: `2.0.0`,
    });

    await p.fixture(
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        resolutions: {dep: `2.0.0`, unused: `1.0.0`},
      }),
    );

    const result = await p.esy(`add dep`);

    expect(
      result.stderr.includes(
        'warn resolution "unused" is unused (defined in package.json)',
      ),
    ).toBe(true);
    expect(
      result.stderr.includes('warn resolution "dep" is unused (defined in package.json)'),
    ).toBe(false);
  });

  test(`resolutions overrides could inject linked packages to non local packages`, async () => {
    const p = await helpers.createTestSandbox();

    await p.defineNpmPackage({
      name: 'dep',
      version: '1.0.0',
    });

    const url = await helpers.getPackageHttpArchivePath(p.npmRegistry, 'dep', '1.0.0');
    const hash = await helpers.getPackageArchiveHash(p.npmRegistry, 'dep', '1.0.0');
    const source = `${url}#${hash}`;

    await p.fixture(
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {dep: '1.0.0'},
        resolutions: {
          dep: {
            source: `${url}#${hash}`,
            override: {
              dependencies: {
                // this path should be resolved against dep's location
                depdep: 'path:./depdep',
              },
            },
          },
        },
      }),
      helpers.dir(
        'depdep',
        helpers.packageJson({
          name: 'depdep',
          version: '1.0.0',
          esy: {},
        }),
      ),
    );

    await p.esy(`install`);

    const layout = await helpers.readInstalledPackages(p.projectPath);
    expect(layout).toMatchObject({
      name: 'root',
      dependencies: {
        dep: {
          name: 'dep',
          version: `archive:${url}#sha1:${hash}`,
          dependencies: {
            depdep: {
              name: 'depdep',
              version: 'path:depdep',
            },
          },
        },
      },
    });
  });
});
