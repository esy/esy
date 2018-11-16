// @flow

const path = require('path');
const helpers = require('../test/helpers.js');

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

    {
      const {stderr} = await p.esy(`add new-dep`);
      expect(stderr).toContain('info solving esy constraints: done');
    }

    await expect(helpers.readInstalledPackages(p.projectPath)).resolves.toMatchObject({
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

    {
      const {stderr, stdout} = await p.esy(`install`);
      expect(stderr).not.toContain('info solving esy constraints: done');
    }
  });

  test(`simply add a new dep with constraint`, async () => {
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

    await p.esy(`add new-dep@^1.0.0`);

    await expect(helpers.readInstalledPackages(p.projectPath)).resolves.toMatchObject({
      dependencies: {
        'new-dep': {
          name: 'new-dep',
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

    {
      const {stderr, stdout} = await p.esy(`install`);
      expect(stderr).not.toContain('info solving esy constraints: done');
    }
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

    await expect(helpers.readInstalledPackages(p.projectPath)).resolves.toMatchObject({
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

    {
      const {stderr, stdout} = await p.esy(`install`);
      expect(stderr).not.toContain('info solving esy constraints: done');
    }
  });
});
