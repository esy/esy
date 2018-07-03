/* @flow */

import type {PackageDriver} from 'pkg-tests-core';

const {join} = require('path');
const {
  fs: {walk, exists},
  tests: {
    getPackageArchivePath,
    getPackageHttpArchivePath,
    getPackageDirectoryPath,
    definePackage,
    defineLocalPackage,
    crawlLayout,
  },
} = require('pkg-tests-core');

module.exports = (makeTemporaryEnv: PackageDriver) => {
  describe(`installing linked packages`, () => {
    test(
      'it should install linked packages',
      makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          esy: true,
          dependencies: {dep: `link:./dep`},
        },
        async ({path, run, source}) => {
          await definePackage({
            name: 'depdep',
            version: '1.0.0',
            esy: true,
          });
          await defineLocalPackage(join(path, 'dep'), {
            name: 'dep',
            version: '1.0.0',
            esy: true,
            dependencies: {
              depdep: '*',
            },
          });

          await run(`install`);

          const layout = await crawlLayout(path);
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
        },
      ),
    );
  });
};
