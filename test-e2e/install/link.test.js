/* @flow */

const {join} = require('path');
const helpers = require('../test/helpers');

helpers.skipSuiteOnWindows();

describe(`installing linked packages`, () => {
  test(
    'it should install linked packages',
    helpers.makeTemporaryEnv(
      {
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {dep: `link:./dep`},
      },
      async ({path, run, source}) => {
        await helpers.definePackage({
          name: 'depdep',
          version: '1.0.0',
          esy: {},
        });
        await helpers.defineLocalPackage(join(path, 'dep'), {
          name: 'dep',
          version: '1.0.0',
          esy: {},
          dependencies: {
            depdep: '*',
          },
        });

        await run(`install`);

        const layout = await helpers.crawlLayout(path);
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
