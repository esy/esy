/* @flow */

const setup = require('./setup');

describe(`Basic tests`, () => {
  test(
    `it should correctly install a single dependency that contains no sub-dependencies`,
    setup.makeTemporaryEnv(
      {
        name: 'root',
        version: '1.0.0',
        esy: {},
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
    setup.makeTemporaryEnv(
      {
        name: 'root',
        version: '1.0.0',
        esy: {},
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
    setup.makeTemporaryEnv(
      {
        name: 'root',
        version: '1.0.0',
        esy: {},
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
    `it should prefer esy._dependenciesForNewEsyInstaller`,
    setup.makeTemporaryEnv(
      {
        name: 'root',
        version: '1.0.0',
        dependencies: {apkg: `1.0.0`},
        esy: {},
      },
      async ({path, run, source}) => {
        await setup.definePackage({
          name: 'apkg',
          version: '1.0.0',
          esy: {
            _dependenciesForNewEsyInstaller: {
              'apkg-dep': `2.0.0`,
            },
          },
          dependencies: {'apkg-dep': `1.0.0`},
        });
        await setup.definePackage({
          name: 'apkg-dep',
          esy: {},
          version: '1.0.0',
        });
        await setup.definePackage({
          name: 'apkg-dep',
          esy: {},
          version: '2.0.0',
        });

        await run(`install`);

        await expect(source(`require('apkg-dep/package.json')`)).resolves.toMatchObject({
          name: 'apkg-dep',
          version: `2.0.0`,
        });
      },
    ),
  );
});
