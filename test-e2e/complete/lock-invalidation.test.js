// @flow

const outdent = require('outdent');
const path = require('path');
const fs = require('fs-extra');
const helpers = require('../test/helpers.js');

const {file, dir, packageJson, dummyExecutable} = helpers;

async function writeJson(filename, json) {
  await fs.writeFile(filename, JSON.stringify(json, null, 2));
}

describe('lock invalidation', () => {
  test('invalidation by adding/remove a dep in a root package', async () => {
    let p = await helpers.createTestSandbox();

    await p.fixture(
      packageJson({
        name: 'root',
        dependencies: {a: '*'},
      }),
    );

    await p.defineNpmPackage({
      name: 'a',
      version: '1.0.0',
    });

    await p.defineNpmPackage({
      name: 'b',
      version: '1.0.0',
    });

    // install

    await p.esy('install');

    expect(await helpers.readInstalledPackages(p.projectPath)).toEqual({
      name: 'root',
      version: 'link-dev:./package.json',
      dependencies: {
        a: {name: 'a', version: '1.0.0', dependencies: {}, devDependencies: {}},
      },
      devDependencies: {},
    });

    // wait, on macOS sometimes it doesn't pick up changes
    await new Promise(resolve => setTimeout(resolve, 1000));

    // add dep & install

    await writeJson(path.join(p.projectPath, 'package.json'), {
      name: 'root',
      dependencies: {a: '*', b: '*'},
    });

    await p.esy('install');

    expect(await helpers.readInstalledPackages(p.projectPath)).toEqual({
      name: 'root',
      version: 'link-dev:./package.json',
      dependencies: {
        a: {name: 'a', version: '1.0.0', dependencies: {}, devDependencies: {}},
        b: {name: 'b', version: '1.0.0', dependencies: {}, devDependencies: {}},
      },
      devDependencies: {},
    });

    // wait, on macOS sometimes it doesn't pick up changes
    await new Promise(resolve => setTimeout(resolve, 1000));

    // remove dep & install

    await writeJson(path.join(p.projectPath, 'package.json'), {
      name: 'root',
      dependencies: {a: '*'},
    });

    await p.esy('install');

    expect(await helpers.readInstalledPackages(p.projectPath)).toEqual({
      name: 'root',
      version: 'link-dev:./package.json',
      dependencies: {
        a: {name: 'a', version: '1.0.0', dependencies: {}, devDependencies: {}},
      },
      devDependencies: {},
    });
  });

  test('invalidation by adding/remove a dep in a linked package', async () => {
    let p = await helpers.createTestSandbox();

    await p.fixture(
      packageJson({
        name: 'root',
        dependencies: {dep: '*'},
        resolutions: {dep: 'link:./dep'},
      }),
      dir(
        'dep',
        packageJson({
          name: 'dep',
          dependencies: {a: '*'},
        }),
      ),
    );

    await p.defineNpmPackage({
      name: 'a',
      version: '1.0.0',
    });

    await p.defineNpmPackage({
      name: 'b',
      version: '1.0.0',
    });

    // install

    await p.esy('install');

    expect(await helpers.readInstalledPackages(p.projectPath)).toEqual({
      name: 'root',
      version: 'link-dev:./package.json',
      dependencies: {
        dep: {
          name: 'dep',
          version: 'link:dep',
          dependencies: {
            a: {name: 'a', version: '1.0.0', dependencies: {}, devDependencies: {}},
          },
          devDependencies: {},
        },
      },
      devDependencies: {},
    });

    // wait, on macOS sometimes it doesn't pick up changes
    await new Promise(resolve => setTimeout(resolve, 1000));

    // add dep & install

    await writeJson(path.join(p.projectPath, 'dep', 'package.json'), {
      name: 'dep',
      dependencies: {a: '*', b: '*'},
    });

    await p.esy('install');

    expect(await helpers.readInstalledPackages(p.projectPath)).toEqual({
      name: 'root',
      version: 'link-dev:./package.json',
      dependencies: {
        dep: {
          name: 'dep',
          version: 'link:dep',
          dependencies: {
            a: {name: 'a', version: '1.0.0', dependencies: {}, devDependencies: {}},
            b: {name: 'b', version: '1.0.0', dependencies: {}, devDependencies: {}},
          },
          devDependencies: {},
        },
      },
      devDependencies: {},
    });

    // wait, on macOS sometimes it doesn't pick up changes
    await new Promise(resolve => setTimeout(resolve, 1000));

    // remove dep & install

    await writeJson(path.join(p.projectPath, 'dep', 'package.json'), {
      name: 'root',
      dependencies: {a: '*'},
    });

    await p.esy('install');

    expect(await helpers.readInstalledPackages(p.projectPath)).toEqual({
      name: 'root',
      version: 'link-dev:./package.json',
      dependencies: {
        dep: {
          name: 'dep',
          version: 'link:dep',
          dependencies: {
            a: {name: 'a', version: '1.0.0', dependencies: {}, devDependencies: {}},
          },
          devDependencies: {},
        },
      },
      devDependencies: {},
    });
  });

  test('invalidation by adding/remove a dep in a root package (in a presence of resolutions)', async () => {
    let p = await helpers.createTestSandbox();

    await p.fixture(
      packageJson({
        name: 'root',
        dependencies: {
          a: '*',
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
          dependencies: {},
        }),
      ),
    );

    await p.defineNpmPackage({
      name: 'a',
      version: '1.0.0',
    });

    await p.defineNpmPackage({
      name: 'b',
      version: '1.0.0',
    });

    // install

    await p.esy('install');

    expect(await helpers.readInstalledPackages(p.projectPath)).toEqual({
      name: 'root',
      version: 'link-dev:./package.json',
      dependencies: {
        a: {name: 'a', version: '1.0.0', dependencies: {}, devDependencies: {}},
        dep: {
          name: 'dep',
          version: 'link:dep',
          dependencies: {},
          devDependencies: {},
        },
      },
      devDependencies: {},
    });

    // wait, on macOS sometimes it doesn't pick up changes
    await new Promise(resolve => setTimeout(resolve, 1000));

    // add dep & install

    await writeJson(path.join(p.projectPath, 'dep', 'package.json'), {
      name: 'dep',
      dependencies: {b: '*'},
    });

    await p.esy('install');

    expect(await helpers.readInstalledPackages(p.projectPath)).toEqual({
      name: 'root',
      version: 'link-dev:./package.json',
      dependencies: {
        a: {name: 'a', version: '1.0.0', dependencies: {}, devDependencies: {}},
        dep: {
          name: 'dep',
          version: 'link:dep',
          dependencies: {
            b: {name: 'b', version: '1.0.0', dependencies: {}, devDependencies: {}},
          },
          devDependencies: {},
        },
      },
      devDependencies: {},
    });

    // wait, on macOS sometimes it doesn't pick up changes
    await new Promise(resolve => setTimeout(resolve, 1000));

    // remove dep & install

    await writeJson(path.join(p.projectPath, 'package.json'), {
      name: 'root',
      dependencies: {
        dep: '*',
      },
      resolutions: {
        dep: 'link:./dep',
      },
    });

    await p.esy('install');

    expect(await helpers.readInstalledPackages(p.projectPath)).toEqual({
      name: 'root',
      version: 'link-dev:./package.json',
      dependencies: {
        dep: {
          name: 'dep',
          version: 'link:dep',
          dependencies: {
            b: {name: 'b', version: '1.0.0', dependencies: {}, devDependencies: {}},
          },
          devDependencies: {},
        },
      },
      devDependencies: {},
    });
  });
});
