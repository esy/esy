// @flow

const path = require('path');
const helpers = require('../test/helpers.js');

describe('Finding project / package root', function() {
  test('finding root with .esyproject', async function() {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      helpers.file('.esyproject', ''),
      helpers.packageJson({
        name: 'root',
      }),
      helpers.dir('subpackage',
        helpers.packageJson({
          name: 'subpackage',
        }),
      )
    );
    p.cd('./subpackage');

    const {stdout} = await p.esy('status --json');
    const status = JSON.parse(stdout);
    expect(status).toMatchObject({
      rootPackageConfigPath: path.join(p.projectPath, 'package.json')
    });
  });

  test('finding root of a named project via @name', async function() {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      helpers.file('package.json', '{}'),
      helpers.file('custom.json', '{}'),
      helpers.dir('subdir')
    );

    {
      const {stdout} = await p.esy('@custom status --json');
      const status = JSON.parse(stdout);
      expect(status).toMatchObject({
        rootPackageConfigPath: path.join(p.projectPath, 'custom.json')
      });
    }

    {
      p.cd('./subdir')
      const {stdout} = await p.esy('@custom status --json');
      const status = JSON.parse(stdout);
      expect(status).toMatchObject({
        rootPackageConfigPath: path.join(p.projectPath, 'custom.json')
      });
    }
  });

  test('finding root of a named project via @name (ignoring package.json upwards)', async function() {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      helpers.file('package.json', '{}'),
      helpers.dir('subdir',
        helpers.file('custom.json', '{}'),
      )
    );

    {
      p.cd('./subdir')
      const {stdout} = await p.esy('@custom status --json');
      const status = JSON.parse(stdout);
      expect(status).toMatchObject({
        rootPackageConfigPath: path.join(p.projectPath, 'subdir', 'custom.json')
      });
    }
  });

  test('finding root of a named project via @name (ignoring .esyproject upwards)', async function() {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      helpers.file('.esyproject', ''),
      helpers.file('package.json', '{}'),
      helpers.dir('subdir',
        helpers.file('custom.json', '{}'),
      )
    );

    {
      p.cd('./subdir')
      const {stdout} = await p.esy('@custom status --json');
      const status = JSON.parse(stdout);
      expect(status).toMatchObject({
        rootPackageConfigPath: path.join(p.projectPath, 'subdir', 'custom.json')
      });
    }
  });

  test('finding root of a named project via @name.json', async function() {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      helpers.file('package.json', '{}'),
      helpers.file('custom.json', '{}'),
      helpers.dir('subdir')
    );

    {
      const {stdout} = await p.esy('@custom.json status --json');
      const status = JSON.parse(stdout);
      expect(status).toMatchObject({
        rootPackageConfigPath: path.join(p.projectPath, 'custom.json')
      });
    }

    {
      p.cd('./subdir')
      const {stdout} = await p.esy('@custom.json status --json');
      const status = JSON.parse(stdout);
      expect(status).toMatchObject({
        rootPackageConfigPath: path.join(p.projectPath, 'custom.json')
      });
    }
  });

  test('finding root of a named project via @/path/name.json', async function() {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      helpers.file('package.json', '{}'),
      helpers.file('custom.json', '{}'),
      helpers.dir('subdir')
    );

    {
      const {stdout} = await p.esy('@./custom.json status --json');
      const status = JSON.parse(stdout);
      expect(status).toMatchObject({
        rootPackageConfigPath: path.join(p.projectPath, 'custom.json')
      });
    }

    {
      p.cd('./subdir')
      const {stdout} = await p.esy('@../custom.json status --json');
      const status = JSON.parse(stdout);
      expect(status).toMatchObject({
        rootPackageConfigPath: path.join(p.projectPath, 'custom.json')
      });
    }
  });
});

