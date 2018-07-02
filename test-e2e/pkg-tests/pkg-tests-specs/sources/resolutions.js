/* @flow */

import type {PackageDriver} from 'pkg-tests-core';

const {
  fs: {walk, exists},
  tests: {
    getPackageArchivePath,
    getPackageHttpArchivePath,
    getPackageDirectoryPath,
    definePackage,
    crawlLayout,
  },
} = require('pkg-tests-core');

module.exports = (makeTemporaryEnv: PackageDriver) => {
  describe(`Installing with resolutions`, () => {
    test(
      `it should prefer resolution over dependencies for the root`,
      makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          esy: true,
          dependencies: {dep: `1.0.0`},
          resolutions: {dep: `2.0.0`},
        },
        async ({path, run, source}) => {
          await definePackage({
            name: 'dep',
            version: '1.0.0',
            esy: true,
          });
          await definePackage({
            name: 'dep',
            version: '2.0.0',
            esy: true,
          });

          await run(`install`);

          const layout = await crawlLayout(path);
          expect(layout).toMatchObject({
            name: 'root',
            dependencies: {
              dep: {
                name: 'dep',
                version: '2.0.0',
              },
            },
          });
        },
      ),
    );

    test(
      `it should prefer resolution over dependencies for the dependency`,
      makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          esy: true,
          dependencies: {dep: `1.0.0`},
          resolutions: {depDep: `2.0.0`},
        },
        async ({path, run, source}) => {
          await definePackage({
            name: 'dep',
            version: '1.0.0',
            esy: true,
            dependencies: {depDep: `1.0.0`},
          });
          await definePackage({
            name: 'depDep',
            esy: true,
            version: '1.0.0',
          });
          await definePackage({
            name: 'depDep',
            esy: true,
            version: '2.0.0',
          });

          await run(`install`);

          const layout = await crawlLayout(path);
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
        },
      ),
    );
  });
};
