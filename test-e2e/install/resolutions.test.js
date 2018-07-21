/* @flow */

const setup = require('./setup');

describe(`Installing with resolutions`, () => {
  test(
    `it should prefer resolution over dependencies for the root`,
    setup.makeTemporaryEnv(
      {
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {dep: `1.0.0`},
        resolutions: {dep: `2.0.0`},
      },
      async ({path, run, source}) => {
        await setup.definePackage({
          name: 'dep',
          version: '1.0.0',
          esy: {},
        });
        await setup.definePackage({
          name: 'dep',
          version: '2.0.0',
          esy: {},
        });

        await run(`install`);

        const layout = await setup.crawlLayout(path);
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
    setup.makeTemporaryEnv(
      {
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {dep: `1.0.0`},
        resolutions: {depDep: `2.0.0`},
      },
      async ({path, run, source}) => {
        await setup.definePackage({
          name: 'dep',
          version: '1.0.0',
          esy: {},
          dependencies: {depDep: `1.0.0`},
        });
        await setup.definePackage({
          name: 'depDep',
          esy: {},
          version: '1.0.0',
        });
        await setup.definePackage({
          name: 'depDep',
          esy: {},
          version: '2.0.0',
        });

        await run(`install`);

        const layout = await setup.crawlLayout(path);
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
