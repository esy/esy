// @flow

const path = require('path');
const helpers = require('../test/helpers.js');

helpers.skipSuiteOnWindows();

describe('adding dependencies', function() {
  test(`simply add a new dep`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {},
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.defineNpmPackage({
      name: 'new-dep',
      version: '1.0.0',
      esy: {},
      dependencies: {},
    });
    await p.defineNpmPackage({
      name: 'new-dep',
      version: '2.0.0',
      esy: {},
      dependencies: {},
    });

    await p.esy(`add new-dep`);

    await expect(helpers.crawlLayout(p.projectPath)).resolves.toMatchObject({
      dependencies: {
        'new-dep': {
          name: 'new-dep',
          version: '2.0.0',
        },
      },
    });

    const packageJsonData = await helpers.readFile(
      path.join(p.projectPath, 'package.json'),
      'utf8',
    );
    const packageJson = JSON.parse(packageJsonData);
    expect(packageJson.dependencies['new-dep']).toEqual('^2.0.0');
  });

  test(`adding multiple deps`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {},
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.defineNpmPackage({
      name: 'new-dep',
      version: '1.0.0',
      esy: {},
      dependencies: {},
    });
    await p.defineNpmPackage({
      name: 'another-new-dep',
      version: '1.0.0',
      esy: {},
      dependencies: {},
    });

    await p.esy(`add new-dep another-new-dep`);

    await expect(helpers.crawlLayout(p.projectPath)).resolves.toMatchObject({
      dependencies: {
        'new-dep': {
          name: 'new-dep',
          version: '1.0.0',
        },
        'another-new-dep': {
          name: 'another-new-dep',
          version: '1.0.0',
        },
      },
    });

    const packageJsonData = await helpers.readFile(
      path.join(p.projectPath, 'package.json'),
      'utf8',
    );
    const packageJson = JSON.parse(packageJsonData);
    expect(packageJson.dependencies['new-dep']).toEqual('^1.0.0');
    expect(packageJson.dependencies['another-new-dep']).toEqual('^1.0.0');
  });
});
