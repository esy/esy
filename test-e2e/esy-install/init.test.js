// @flow

const path = require('path');
const helpers = require('../test/helpers.js');

describe('init esy-project', function() {
  test(`creates an esy.json skeleton`, async () => {
    const p = await helpers.createTestSandbox();

    await p.esy(`init`);
    const packageJsonData = await helpers.readFile(
      path.join(p.projectPath, 'esy.json'),
      'utf8',
    );
    const packageJson = JSON.parse(packageJsonData);

    expect(packageJson).toMatchObject({
      name: 'project',
      version: '0.1.0',
      esy: {},
      scripts: {},
      dependencies: {},
      devDependencies: {},
    });
  });

  test(`does not overwrite existing esy.json without -f`, async () => {
    const fixture = [
      helpers.packageJson(
        {
          already: 'created',
        },
        'esy.json',
      ),
    ];

    const p = await helpers.createTestSandbox(...fixture);

    await p.esy(`init`);

    const packageJsonData = await helpers.readFile(
      path.join(p.projectPath, 'esy.json'),
      'utf8',
    );

    const packageJson = JSON.parse(packageJsonData);

    expect(packageJson).toMatchObject({
      already: 'created',
    });
  });

  test(`should overwrite existing esy.json with -f`, async () => {
    const fixture = [
      helpers.packageJson(
        {
          already: 'created',
        },
        'esy.json',
      ),
    ];

    const p = await helpers.createTestSandbox(...fixture);

    await p.esy(`init -f`);

    const packageJsonData = await helpers.readFile(
      path.join(p.projectPath, 'esy.json'),
      'utf8',
    );

    const packageJson = JSON.parse(packageJsonData);

    expect(packageJson).toMatchObject({
      name: 'project',
      version: '0.1.0',
      esy: {},
      scripts: {},
      dependencies: {},
      devDependencies: {},
    });
  });
});
