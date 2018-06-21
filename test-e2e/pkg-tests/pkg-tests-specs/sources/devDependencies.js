/* @flow */

import type {PackageDriver} from 'pkg-tests-core';

const {
  fs: {walk, exists},
  tests: {
    crawlLayout,
    getPackageArchivePath,
    getPackageHttpArchivePath,
    getPackageDirectoryPath,
    definePackage,
  },
} = require('pkg-tests-core');

module.exports = (makeTemporaryEnv: PackageDriver) => {
  describe('Installing devDependencies', function() {
    test(
      `it should install devDependencies`,
      makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          devDependencies: {devDep: `1.0.0`},
        },
        async ({path, run, source}) => {
          await definePackage({
            name: 'devDep',
            version: '1.0.0',
            dependencies: {},
          });

          await run(`install`);

          await expect(crawlLayout(path)).resolves.toMatchObject({
            dependencies: {
              devDep: {
                name: 'devDep',
              },
            },
          });
        },
      ),
    );

    test(
      `it should install devDependencies along with its deps`,
      makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          devDependencies: {devDep: `1.0.0`},
        },
        async ({path, run, source}) => {
          await definePackage({
            name: 'devDep',
            version: '1.0.0',
            dependencies: {
              ok: '1.0.0',
            },
          });
          await definePackage({
            name: 'ok',
            version: '1.0.0',
            dependencies: {},
          });

          await run(`install`);

          await expect(crawlLayout(path)).resolves.toMatchObject({
            dependencies: {
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
        },
      ),
    );

    test(
      `it should allow to duplicate conflicting deps between devDependencies and runtime deps`,
      makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          dependencies: {ok: `1.0.0`},
          devDependencies: {devDep: `1.0.0`},
        },
        async ({path, run, source}) => {
          await definePackage({
            name: 'devDep',
            version: '1.0.0',
            dependencies: {
              ok: '2.0.0',
            },
          });
          await definePackage({
            name: 'ok',
            version: '1.0.0',
            dependencies: {},
          });
          await definePackage({
            name: 'ok',
            version: '2.0.0',
            dependencies: {},
          });

          await run(`install`);

          await expect(crawlLayout(path)).resolves.toMatchObject({
            dependencies: {
              ok: {
                name: 'ok',
                version: '1.0.0',
              },
              devDep: {
                name: 'devDep',
                dependencies: {
                  ok: {
                    name: 'ok',
                    version: '2.0.0',
                  },
                },
              },
            },
          });
        },
      ),
    );

    test(
      `it should prefer an already installed version when solving devDeps deps`,
      makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          dependencies: {ok: `1.0.0`},
          devDependencies: {devDep: `1.0.0`},
        },
        async ({path, run, source}) => {
          await definePackage({
            name: 'devDep',
            version: '1.0.0',
            dependencies: {
              ok: '*',
            },
          });
          await definePackage({
            name: 'ok',
            version: '1.0.0',
            dependencies: {},
          });
          await definePackage({
            name: 'ok',
            version: '2.0.0',
            dependencies: {},
          });

          await run(`install`);

          const layout = await crawlLayout(path);
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
        },
      ),
    );

    test(
      `it should handle two devDeps sharing a dep`,
      makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          devDependencies: {devDep: `1.0.0`, devDep2: '1.0.0'},
        },
        async ({path, run, source}) => {
          await definePackage({
            name: 'devDep',
            version: '1.0.0',
            dependencies: {
              ok: '*',
            },
          });
          await definePackage({
            name: 'devDep2',
            version: '1.0.0',
            dependencies: {
              ok: '*',
            },
          });
          await definePackage({
            name: 'ok',
            version: '1.0.0',
            dependencies: {},
          });

          await run(`install`);

          const layout = await crawlLayout(path);
          await expect(layout).toMatchObject({
            dependencies: {
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
          expect(layout).not.toHaveProperty('dependencies.ok');
        },
      ),
    );

    test(
      `it should handle two devDeps having conflicting dep`,
      makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          devDependencies: {devDep: `1.0.0`, devDep2: '1.0.0'},
        },
        async ({path, run, source}) => {
          await definePackage({
            name: 'devDep',
            version: '1.0.0',
            dependencies: {
              ok: '^1',
            },
          });
          await definePackage({
            name: 'devDep2',
            version: '1.0.0',
            dependencies: {
              ok: '^2',
            },
          });
          await definePackage({
            name: 'ok',
            version: '1.0.0',
            dependencies: {},
          });
          await definePackage({
            name: 'ok',
            version: '2.0.0',
            dependencies: {},
          });

          await run(`install`);

          const layout = await crawlLayout(path);
          await expect(layout).toMatchObject({
            dependencies: {
              devDep: {
                name: 'devDep',
                dependencies: {
                  ok: {
                    name: 'ok',
                    version: '1.0.0',
                  },
                },
              },
              devDep2: {
                name: 'devDep2',
                dependencies: {
                  ok: {
                    name: 'ok',
                    version: '2.0.0',
                  },
                },
              },
            },
          });
          expect(layout).not.toHaveProperty('dependencies.ok');
        },
      ),
    );
  });
};
