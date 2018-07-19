/* @flow */

const tests = require('./setup');

describe('Installing devDependencies', function() {
  test(
    `it should install devDependencies`,
    tests.makeTemporaryEnv(
      {
        name: 'root',
        version: '1.0.0',
        esy: {},
        devDependencies: {devDep: `1.0.0`},
      },
      async ({path, run, source}) => {
        await tests.definePackage({
          name: 'devDep',
          version: '1.0.0',
          esy: {},
          dependencies: {},
        });

        await run(`install`);

        await expect(tests.crawlLayout(path)).resolves.toMatchObject({
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
    tests.makeTemporaryEnv(
      {
        name: 'root',
        version: '1.0.0',
        esy: {},
        devDependencies: {devDep: `1.0.0`},
      },
      async ({path, run, source}) => {
        await tests.definePackage({
          name: 'devDep',
          version: '1.0.0',
          esy: {},
          dependencies: {
            ok: '1.0.0',
          },
        });
        await tests.definePackage({
          name: 'ok',
          version: '1.0.0',
          esy: {},
          dependencies: {},
        });

        await run(`install`);

        await expect(tests.crawlLayout(path)).resolves.toMatchObject({
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
    tests.makeTemporaryEnv(
      {
        name: 'root',
        version: '1.0.0',
        dependencies: {ok: `1.0.0`},
        esy: {},
        devDependencies: {devDep: `1.0.0`},
      },
      async ({path, run, source}) => {
        await tests.definePackage({
          name: 'devDep',
          version: '1.0.0',
          esy: {},
          dependencies: {
            ok: '*',
          },
        });
        await tests.definePackage({
          name: 'ok',
          version: '1.0.0',
          esy: {},
          dependencies: {},
        });
        await tests.definePackage({
          name: 'ok',
          version: '2.0.0',
          esy: {},
          dependencies: {},
        });

        await run(`install`);

        const layout = await tests.crawlLayout(path);
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
    tests.makeTemporaryEnv(
      {
        name: 'root',
        version: '1.0.0',
        esy: {},
        devDependencies: {devDep: `1.0.0`, devDep2: '1.0.0'},
      },
      async ({path, run, source}) => {
        await tests.definePackage({
          name: 'devDep',
          version: '1.0.0',
          esy: {},
          dependencies: {
            ok: '*',
          },
        });
        await tests.definePackage({
          name: 'devDep2',
          version: '1.0.0',
          esy: {},
          dependencies: {
            ok: '*',
          },
        });
        await tests.definePackage({
          name: 'ok',
          version: '1.0.0',
          esy: {},
          dependencies: {},
        });

        await run(`install`);

        const layout = await tests.crawlLayout(path);
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
