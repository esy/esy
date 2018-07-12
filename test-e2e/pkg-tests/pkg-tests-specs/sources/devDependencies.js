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
          esy: {},
          devDependencies: {devDep: `1.0.0`},
        },
        async ({path, run, source}) => {
          await definePackage({
            name: 'devDep',
            version: '1.0.0',
            esy: {},
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
          esy: {},
          devDependencies: {devDep: `1.0.0`},
        },
        async ({path, run, source}) => {
          await definePackage({
            name: 'devDep',
            version: '1.0.0',
            esy: {},
            dependencies: {
              ok: '1.0.0',
            },
          });
          await definePackage({
            name: 'ok',
            version: '1.0.0',
            esy: {},
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
                dependencies: {},
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
          esy: {},
          devDependencies: {devDep: `1.0.0`},
        },
        async ({path, run, source}) => {
          await definePackage({
            name: 'devDep',
            version: '1.0.0',
            esy: {},
            dependencies: {
              ok: '*',
            },
          });
          await definePackage({
            name: 'ok',
            version: '1.0.0',
            esy: {},
            dependencies: {},
          });
          await definePackage({
            name: 'ok',
            version: '2.0.0',
            esy: {},
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
          esy: {},
          devDependencies: {devDep: `1.0.0`, devDep2: '1.0.0'},
        },
        async ({path, run, source}) => {
          await definePackage({
            name: 'devDep',
            version: '1.0.0',
            esy: {},
            dependencies: {
              ok: '*',
            },
          });
          await definePackage({
            name: 'devDep2',
            version: '1.0.0',
            esy: {},
            dependencies: {
              ok: '*',
            },
          });
          await definePackage({
            name: 'ok',
            version: '1.0.0',
            esy: {},
            dependencies: {},
          });

          await run(`install`);

          const layout = await crawlLayout(path);
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
        },
      ),
    );
  });
};
