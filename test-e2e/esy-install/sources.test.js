/* @flow */

const helpers = require('../test/helpers.js');

async function assertLayoutCorrect(path) {
  await expect(helpers.readInstalledPackages(path)).resolves.toMatchObject({
    dependencies: {
      'example-yarn-package': {
        name: 'example-yarn-package',
        dependencies: {
          lodash: {
            name: 'lodash',
          },
        },
      },
    },
  });
}

describe(`Tests for installations from custom sources`, () => {
  describe('Installation from github', () => {
    test('it should install without ref', async () => {
      const fixture = [
        helpers.packageJson({
          name: 'root',
          version: '1.0.0',
          dependencies: {'example-yarn-package': `yarnpkg/example-yarn-package`},
        }),
      ];
      const p = await helpers.createTestSandbox(...fixture);
      await p.defineNpmPackage({
        name: 'lodash',
        version: '4.24.0',
      });
      await p.esy('install --skip-repository-update');
      await assertLayoutCorrect(p.projectPath);
    });

    test('it should install with branch as ref', async () => {
      const fixture = [
        helpers.packageJson({
          name: 'root',
          version: '1.0.0',
          dependencies: {'example-yarn-package': `yarnpkg/example-yarn-package#master`},
        }),
      ];
      const p = await helpers.createTestSandbox(...fixture);
      await p.defineNpmPackage({
        name: 'lodash',
        version: '4.24.0',
      });
      await p.esy('install --skip-repository-update');
      await assertLayoutCorrect(p.projectPath);
    });

    test('it should install with 6 char commit sha as ref', async () => {
      const fixture = [
        helpers.packageJson({
          name: 'root',
          version: '1.0.0',
          dependencies: {'example-yarn-package': `yarnpkg/example-yarn-package#0b8f43`},
        }),
      ];
      const p = await helpers.createTestSandbox(...fixture);
      await p.defineNpmPackage({
        name: 'lodash',
        version: '4.24.0',
      });
      await p.esy('install --skip-repository-update');
      await assertLayoutCorrect(p.projectPath);
    });

    test('it should install with 9 char commit sha as ref', async () => {
      const fixture = [
        helpers.packageJson({
          name: 'root',
          version: '1.0.0',
          dependencies: {
            'example-yarn-package': `yarnpkg/example-yarn-package#0b8f43f77`,
          },
        }),
      ];
      const p = await helpers.createTestSandbox(...fixture);
      await p.defineNpmPackage({
        name: 'lodash',
        version: '4.24.0',
      });
      await p.esy('install --skip-repository-update');
      await assertLayoutCorrect(p.projectPath);
    });

    test('it should install with 40 char commit sha as ref', async () => {
      const fixture = [
        helpers.packageJson({
          name: 'root',
          version: '1.0.0',
          dependencies: {
            'example-yarn-package': `yarnpkg/example-yarn-package#0b8f43f77361ff7739bcb42de7787b09208bcece`,
          },
        }),
      ];
      const p = await helpers.createTestSandbox(...fixture);
      await p.defineNpmPackage({
        name: 'lodash',
        version: '4.24.0',
      });
      await p.esy('install --skip-repository-update');
      await assertLayoutCorrect(p.projectPath);
    });
  });

  describe('Installation from git', () => {
    test('install from git+https:// with no ref', async () => {
      const fixture = [
        helpers.packageJson({
          name: 'root',
          version: '1.0.0',
          dependencies: {
            'example-yarn-package': `git+https://github.com/yarnpkg/example-yarn-package.git`,
          },
        }),
      ];
      const p = await helpers.createTestSandbox(...fixture);
      await p.defineNpmPackage({
        name: 'lodash',
        version: '4.24.0',
      });
      await p.esy('install --skip-repository-update');
      await assertLayoutCorrect(p.projectPath);
    });

    test('install from git+https:// with branch as ref', async () => {
      const fixture = [
        helpers.packageJson({
          name: 'root',
          version: '1.0.0',
          dependencies: {
            'example-yarn-package': `git+https://github.com/yarnpkg/example-yarn-package.git#master`,
          },
        }),
      ];
      const p = await helpers.createTestSandbox(...fixture);
      await p.defineNpmPackage({
        name: 'lodash',
        version: '4.24.0',
      });
      await p.esy('install --skip-repository-update');
      await assertLayoutCorrect(p.projectPath);
    });

    test('install from git+https:// with commit sha as ref', async () => {
      const fixture = [
        helpers.packageJson({
          name: 'root',
          version: '1.0.0',
          dependencies: {
            'example-yarn-package': `git+https://github.com/yarnpkg/example-yarn-package.git#0b8f43`,
          },
        }),
      ];
      const p = await helpers.createTestSandbox(...fixture);
      await p.defineNpmPackage({
        name: 'lodash',
        version: '4.24.0',
      });
      await p.esy('install --skip-repository-update');
      await assertLayoutCorrect(p.projectPath);
    });

    test('install from git:// with no ref', async () => {
      const fixture = [
        helpers.packageJson({
          name: 'root',
          version: '1.0.0',
          dependencies: {
            'example-yarn-package': `git://github.com/yarnpkg/example-yarn-package.git`,
          },
        }),
      ];
      const p = await helpers.createTestSandbox(...fixture);
      await p.defineNpmPackage({
        name: 'lodash',
        version: '4.24.0',
      });
      await p.esy('install --skip-repository-update');
      await assertLayoutCorrect(p.projectPath);
    });

    test('install from git:// with branch as ref', async () => {
      const fixture = [
        helpers.packageJson({
          name: 'root',
          version: '1.0.0',
          dependencies: {
            'example-yarn-package': `git://github.com/yarnpkg/example-yarn-package.git#master`,
          },
        }),
      ];
      const p = await helpers.createTestSandbox(...fixture);
      await p.defineNpmPackage({
        name: 'lodash',
        version: '4.24.0',
      });
      await p.esy('install --skip-repository-update');
      await assertLayoutCorrect(p.projectPath);
    });

    test('install from git:// with commit as ref', async () => {
      const fixture = [
        helpers.packageJson({
          name: 'root',
          version: '1.0.0',
          dependencies: {
            'example-yarn-package': `git://github.com/yarnpkg/example-yarn-package.git#0b8f43`,
          },
        }),
      ];
      const p = await helpers.createTestSandbox(...fixture);
      await p.defineNpmPackage({
        name: 'lodash',
        version: '4.24.0',
      });
      await p.esy('install --skip-repository-update');
      await assertLayoutCorrect(p.projectPath);
    });
  });

  test('install from https://', async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {
          'example-yarn-package':
            'https://codeload.github.com/yarnpkg/example-yarn-package/tar.gz/0b8f43#02988284bf71a3584f1809c513a2eebd51341911',
        },
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.defineNpmPackage({
      name: 'lodash',
      version: '4.24.0',
    });
    await p.esy('install --skip-repository-update');
    await assertLayoutCorrect(p.projectPath);
  });
});

describe('resolutions', function() {
  test('github ssh URL', async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {
          'example-yarn-package': '*',
        },
        resolutions: {
          'example-yarn-package':
            'git+ssh://git@github.com:yarnpkg/example-yarn-package.git#0b8f43f',
        },
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.defineNpmPackage({
      name: 'lodash',
      version: '4.24.0',
    });
    await p.esy('install --skip-repository-update');
    await assertLayoutCorrect(p.projectPath);
  });

  test('github ssh URL (via git:)', async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {
          'example-yarn-package': '*',
        },
        resolutions: {
          'example-yarn-package':
            'git:git+ssh://git@github.com:yarnpkg/example-yarn-package.git#0b8f43f',
        },
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.defineNpmPackage({
      name: 'lodash',
      version: '4.24.0',
    });
    await p.esy('install --skip-repository-update');
    await assertLayoutCorrect(p.projectPath);
  });

  test('github ssh (via git:)', async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {
          'example-yarn-package': '*',
        },
        resolutions: {
          'example-yarn-package':
            'git:git@github.com:yarnpkg/example-yarn-package.git#0b8f43f',
        },
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.defineNpmPackage({
      name: 'lodash',
      version: '4.24.0',
    });
    await p.esy('install --skip-repository-update');
    await assertLayoutCorrect(p.projectPath);
  });


  test('github ssh URL with manifest', async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {
          'example-yarn-package': '*',
        },
        resolutions: {
          'example-yarn-package':
            'git+ssh://git@github.com:yarnpkg/example-yarn-package.git:package.json#0b8f43f',
        },
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.defineNpmPackage({
      name: 'lodash',
      version: '4.24.0',
    });
    await p.esy('install --skip-repository-update');
    await assertLayoutCorrect(p.projectPath);
  });

  test('github ssh URL (via git:) with manifest', async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {
          'example-yarn-package': '*',
        },
        resolutions: {
          'example-yarn-package':
            'git:git+ssh://git@github.com:yarnpkg/example-yarn-package.git:package.json#0b8f43f',
        },
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.defineNpmPackage({
      name: 'lodash',
      version: '4.24.0',
    });
    await p.esy('install --skip-repository-update');
    await assertLayoutCorrect(p.projectPath);
  });

  test('github ssh (via git:) with manifest', async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {
          'example-yarn-package': '*',
        },
        resolutions: {
          'example-yarn-package':
            'git:git@github.com:yarnpkg/example-yarn-package.git:package.json#0b8f43f',
        },
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.defineNpmPackage({
      name: 'lodash',
      version: '4.24.0',
    });
    await p.esy('install --skip-repository-update');
    await assertLayoutCorrect(p.projectPath);
  });


  test('github https URL', async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {
          'example-yarn-package': '*',
        },
        resolutions: {
          'example-yarn-package':
            'git+https://github.com/yarnpkg/example-yarn-package.git#0b8f43f',
        },
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.defineNpmPackage({
      name: 'lodash',
      version: '4.24.0',
    });
    await p.esy('install --skip-repository-update');
    await assertLayoutCorrect(p.projectPath);
  });

  test('github https URL (via git:)', async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {
          'example-yarn-package': '*',
        },
        resolutions: {
          'example-yarn-package':
            'git:git+https://github.com/yarnpkg/example-yarn-package.git#0b8f43f',
        },
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.defineNpmPackage({
      name: 'lodash',
      version: '4.24.0',
    });
    await p.esy('install --skip-repository-update');
    await assertLayoutCorrect(p.projectPath);
  });
});
