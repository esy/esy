/* @flow */

import type {PackageDriver} from 'pkg-tests-core';

const {
  fs: {walk, exists},
  tests: {
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

          await expect(source(`require('devDep/package.json')`)).resolves.toMatchObject(
            {
              name: 'devDep',
              version: `1.0.0`,
            },
          );
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
              'apkg-dep': '1.0.0',
            },
          });
          await definePackage({
            name: 'apkg-dep',
            version: '1.0.0',
            dependencies: {},
          });

          await run(`install`);

          await expect(source(`require('./node_modules/devDep/package.json')`)).resolves.toMatchObject(
            {
              name: 'devDep',
              version: `1.0.0`,
            },
          );
          await expect(source(`require('./node_modules/devDep/node_modules/apkg-dep/package.json')`)).resolves.toMatchObject(
            {
              name: 'apkg-dep',
              version: `1.0.0`,
            },
          );
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
              'ok': '2.0.0',
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

          await expect(source(`require('./node_modules/ok/package.json')`)).resolves.toMatchObject(
            {
              name: 'ok',
              version: `1.0.0`,
            },
          );
          await expect(source(`require('./node_modules/devDep/package.json')`)).resolves.toMatchObject(
            {
              name: 'devDep',
              version: `1.0.0`,
            },
          );
          await expect(source(`require('./node_modules/devDep/node_modules/ok/package.json')`)).resolves.toMatchObject(
            {
              name: 'ok',
              version: `2.0.0`,
            },
          );
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
              'ok': '*',
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

          await expect(source(`require('./node_modules/ok/package.json')`)).resolves.toMatchObject(
            {
              name: 'ok',
              version: `1.0.0`,
            },
          );
          await expect(source(`require('./node_modules/devDep/package.json')`)).resolves.toMatchObject(
            {
              name: 'devDep',
              version: `1.0.0`,
            },
          );
          expect(await exists(path + '/node_modules/devDep/node_modules/ok/package.json')).toBe(false);
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
              'ok': '*',
            },
          });
          await definePackage({
            name: 'devDep2',
            version: '1.0.0',
            dependencies: {
              'ok': '*',
            },
          });
          await definePackage({
            name: 'ok',
            version: '1.0.0',
            dependencies: {},
          });

          await run(`install`);

          await expect(source(`require('./node_modules/devDep/package.json')`)).resolves.toMatchObject(
            {
              name: 'devDep',
              version: `1.0.0`,
            },
          );
          await expect(source(`require('./node_modules/devDep2/package.json')`)).resolves.toMatchObject(
            {
              name: 'devDep2',
              version: `1.0.0`,
            },
          );
          await expect(source(`require('./node_modules/devDep/node_modules/ok/package.json')`)).resolves.toMatchObject(
            {
              name: 'ok',
              version: `1.0.0`,
            },
          );
          await expect(source(`require('./node_modules/devDep2/node_modules/ok/package.json')`)).resolves.toMatchObject(
            {
              name: 'ok',
              version: `1.0.0`,
            },
          );
        },
      ),
    );
  });
};

