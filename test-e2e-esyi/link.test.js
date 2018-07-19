/* @flow */

const {join} = require('path');
const setup = require('./setup');

describe(`installing linked packages`, () => {
  test(
    'it should install linked packages',
    setup.makeTemporaryEnv(
      {
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {dep: `link:./dep`},
      },
      async ({path, run, source}) => {
        await setup.definePackage({
          name: 'depdep',
          version: '1.0.0',
          esy: {},
        });
        await setup.defineLocalPackage(join(path, 'dep'), {
          name: 'dep',
          version: '1.0.0',
          esy: {},
          dependencies: {
            depdep: '*',
          },
        });

        await run(`install`);

        const layout = await setup.crawlLayout(path);
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
