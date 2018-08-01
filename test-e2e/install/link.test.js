/* @flow */

const path = require('path');
const helpers = require('../test/helpers');

helpers.skipSuiteOnWindows();

describe(`installing linked packages`, () => {
  test('it should install linked packages', async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {dep: `link:./dep`},
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);

    await p.defineNpmPackage({
      name: 'depdep',
      version: '1.0.0',
      esy: {},
    });
    await p.defineNpmLocalPackage(path.join(p.projectPath, 'dep'), {
      name: 'dep',
      version: '1.0.0',
      esy: {},
      dependencies: {
        depdep: '*',
      },
    });

    await p.esy(`install`);

    const layout = await helpers.crawlLayout(p.projectPath);
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
  });
});
