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
  describe(`Basic tests`, () => {
    test(
      `it should correctly install a single dependency that contains no sub-dependencies`,
      makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          dependencies: {[`no-deps`]: `1.0.0`},
        },
        async ({path, run, source}) => {
          await run(`install`);

          await expect(source(`require('no-deps')`)).resolves.toMatchObject({
            name: `no-deps`,
            version: `1.0.0`,
          });
        },
      ),
    );

    test(
      `it should correctly install a dependency that itself contains a fixed dependency`,
      makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          dependencies: {[`one-fixed-dep`]: `1.0.0`},
        },
        async ({path, run, source}) => {
          await run(`install`);

          await expect(source(`require('one-fixed-dep')`)).resolves.toMatchObject({
            name: `one-fixed-dep`,
            version: `1.0.0`,
            dependencies: {
              [`no-deps`]: {
                name: `no-deps`,
                version: `1.0.0`,
              },
            },
          });
        },
      ),
    );

    test(
      `it should correctly install a dependency that itself contains a range dependency`,
      makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          dependencies: {[`one-range-dep`]: `1.0.0`},
        },
        async ({path, run, source}) => {
          await run(`install`);

          await expect(source(`require('one-range-dep')`)).resolves.toMatchObject({
            name: `one-range-dep`,
            version: `1.0.0`,
            dependencies: {
              [`no-deps`]: {
                name: `no-deps`,
                version: `1.1.0`,
              },
            },
          });
        },
      ),
    );

    test(
      `it should prefer resolution over dependencies for the root`,
      makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          dependencies: {'dep-via-resolution': `1.0.0`},
          resolutions: {'dep-via-resolution': `2.0.0`},
        },
        async ({path, run, source}) => {
          await definePackage({
            name: 'dep-via-resolution',
            version: '1.0.0',
          });
          await definePackage({
            name: 'dep-via-resolution',
            version: '2.0.0',
          });

          await run(`install`);

          await expect(
            source(`require('dep-via-resolution/package.json')`),
          ).resolves.toMatchObject({
            name: `dep-via-resolution`,
            version: `2.0.0`,
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
          dependencies: {apkg: `1.0.0`},
          resolutions: {'apkg-dep': `2.0.0`},
        },
        async ({path, run, source}) => {
          await definePackage({
            name: 'apkg',
            version: '1.0.0',
            dependencies: {'apkg-dep': `1.0.0`},
          });
          await definePackage({
            name: 'apkg-dep',
            version: '1.0.0',
          });
          await definePackage({
            name: 'apkg-dep',
            version: '2.0.0',
          });

          await run(`install`);

          await expect(source(`require('apkg-dep/package.json')`)).resolves.toMatchObject(
            {
              name: 'apkg-dep',
              version: `2.0.0`,
            },
          );
        },
      ),
    );

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

    test.skip(
      `it should correctly install an inter-dependency loop`,
      makeTemporaryEnv(
        {
          name: 'root',
          version: '1.0.0',
          dependencies: {[`dep-loop-entry`]: `1.0.0`},
        },
        async ({path, run, source}) => {
          await run(`print-cudf-universe`);
          await run(`install`);

          await expect(
            source(
              // eslint-disable-next-line
              `require('dep-loop-entry') === require('dep-loop-entry').dependencies['dep-loop-exit'].dependencies['dep-loop-entry']`,
            ),
          );
        },
      ),
    );

    test.skip(
      `it should install from archives on the filesystem`,
      makeTemporaryEnv(
        {
          dependencies: {[`no-deps`]: getPackageArchivePath(`no-deps`, `1.0.0`)},
        },
        async ({path, run, source}) => {
          await run(`install`);

          await expect(source(`require('no-deps')`)).resolves.toMatchObject({
            name: `no-deps`,
            version: `1.0.0`,
          });
        },
      ),
    );

    test.skip(
      `it should install the dependencies of any dependency fetched from the filesystem`,
      makeTemporaryEnv(
        {
          dependencies: {
            [`one-fixed-dep`]: getPackageArchivePath(`one-fixed-dep`, `1.0.0`),
          },
        },
        async ({path, run, source}) => {
          await run(`install`);

          await expect(source(`require('one-fixed-dep')`)).resolves.toMatchObject({
            name: `one-fixed-dep`,
            version: `1.0.0`,
            dependencies: {
              [`no-deps`]: {
                name: `no-deps`,
                version: `1.0.0`,
              },
            },
          });
        },
      ),
    );

    test.skip(
      `it should install from files on the internet`,
      makeTemporaryEnv(
        {
          dependencies: {[`no-deps`]: getPackageHttpArchivePath(`no-deps`, `1.0.0`)},
        },
        async ({path, run, source}) => {
          await run(`install`);

          await expect(source(`require('no-deps')`)).resolves.toMatchObject({
            name: `no-deps`,
            version: `1.0.0`,
          });
        },
      ),
    );

    test.skip(
      `it should install the dependencies of any dependency fetched from the internet`,
      makeTemporaryEnv(
        {
          dependencies: {
            [`one-fixed-dep`]: getPackageHttpArchivePath(`one-fixed-dep`, `1.0.0`),
          },
        },
        async ({path, run, source}) => {
          await run(`install`);

          await expect(source(`require('one-fixed-dep')`)).resolves.toMatchObject({
            name: `one-fixed-dep`,
            version: `1.0.0`,
            dependencies: {
              [`no-deps`]: {
                name: `no-deps`,
                version: `1.0.0`,
              },
            },
          });
        },
      ),
    );

    test.skip(
      `it should install from local directories`,
      makeTemporaryEnv(
        {
          dependencies: {[`no-deps`]: getPackageDirectoryPath(`no-deps`, `1.0.0`)},
        },
        async ({path, run, source}) => {
          await run(`install`);

          await expect(source(`require('no-deps')`)).resolves.toMatchObject({
            name: `no-deps`,
            version: `1.0.0`,
          });
        },
      ),
    );

    test.skip(
      `it should install the dependencies of any dependency fetched from a local directory`,
      makeTemporaryEnv(
        {
          dependencies: {
            [`one-fixed-dep`]: getPackageDirectoryPath(`one-fixed-dep`, `1.0.0`),
          },
        },
        async ({path, run, source}) => {
          await run(`install`);

          await expect(source(`require('one-fixed-dep')`)).resolves.toMatchObject({
            name: `one-fixed-dep`,
            version: `1.0.0`,
            dependencies: {
              [`no-deps`]: {
                name: `no-deps`,
                version: `1.0.0`,
              },
            },
          });
        },
      ),
    );

    test.skip(
      `it should correctly create resolution mounting points when using the link protocol`,
      makeTemporaryEnv(
        {
          dependencies: {
            [`link-dep`]: (async () =>
              `link:${await getPackageDirectoryPath(`no-deps`, `1.0.0`)}`)(),
          },
        },
        async ({path, run, source}) => {
          await run(`install`);

          await expect(source(`require('link-dep')`)).resolves.toMatchObject({
            name: `no-deps`,
            version: `1.0.0`,
          });
        },
      ),
    );
  });
};
