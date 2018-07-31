/* @flow */

const helpers = require('../test/helpers.js');

helpers.skipSuiteOnWindows();

describe('Installing devDependencies', function() {
  test(
    `it should install devDependencies`,
    helpers.makeTemporaryEnv(
      {
        name: 'root',
        version: '1.0.0',
        esy: {},
        devDependencies: {devDep: `1.0.0`},
      },
      async ({path, run, source}) => {
        await helpers.definePackage({
          name: 'devDep',
          version: '1.0.0',
          esy: {},
          dependencies: {},
        });

        await run(`install`);

        await expect(helpers.crawlLayout(path)).resolves.toMatchObject({
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
    helpers.makeTemporaryEnv(
      {
        name: 'root',
        version: '1.0.0',
        esy: {},
        devDependencies: {devDep: `1.0.0`},
      },
      async ({path, run, source}) => {
        await helpers.definePackage({
          name: 'devDep',
          version: '1.0.0',
          esy: {},
          dependencies: {
            ok: '1.0.0',
          },
        });
        await helpers.definePackage({
          name: 'ok',
          version: '1.0.0',
          esy: {},
          dependencies: {},
        });

        await run(`install`);

        await expect(helpers.crawlLayout(path)).resolves.toMatchObject({
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
    helpers.makeTemporaryEnv(
      {
        name: 'root',
        version: '1.0.0',
        dependencies: {ok: `1.0.0`},
        esy: {},
        devDependencies: {devDep: `1.0.0`},
      },
      async ({path, run, source}) => {
        await helpers.definePackage({
          name: 'devDep',
          version: '1.0.0',
          esy: {},
          dependencies: {
            ok: '*',
          },
        });
        await helpers.definePackage({
          name: 'ok',
          version: '1.0.0',
          esy: {},
          dependencies: {},
        });
        await helpers.definePackage({
          name: 'ok',
          version: '2.0.0',
          esy: {},
          dependencies: {},
        });

        await run(`install`);

        const layout = await helpers.crawlLayout(path);
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
    helpers.makeTemporaryEnv(
      {
        name: 'root',
        version: '1.0.0',
        esy: {},
        devDependencies: {devDep: `1.0.0`, devDep2: '1.0.0'},
      },
      async ({path, run, source}) => {
        await helpers.definePackage({
          name: 'devDep',
          version: '1.0.0',
          esy: {},
          dependencies: {
            ok: '*',
          },
        });
        await helpers.definePackage({
          name: 'devDep2',
          version: '1.0.0',
          esy: {},
          dependencies: {
            ok: '*',
          },
        });
        await helpers.definePackage({
          name: 'ok',
          version: '1.0.0',
          esy: {},
          dependencies: {},
        });

        await run(`install`);

        const layout = await helpers.crawlLayout(path);
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
