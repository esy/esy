// @flow

const path = require('path');
const fs = require('fs-extra');
const helpers = require('../test/helpers.js');

describe('offline installation workflow', function() {
  test('fetch: it can store source tarballs in a local directory', async function() {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      helpers.packageJson({
        name: 'root',
        dependencies: {
          a: '*',
          b: '*',
        },
      }),
    );

    await p.defineNpmPackage({
      name: 'a',
      version: '1.0.0',
    });

    await p.defineNpmPackage({
      name: 'b',
      version: '2.0.0',
    });

    const tarballsPath = path.join(p.projectPath, 'sources');

    await p.esy(`install --cache-tarballs-path ${tarballsPath}`);

    await fs.exists(tarballsPath);

    // remove caches
    await fs.remove(path.join(p.projectPath, '_esy'));
    await fs.remove(path.join(p.esyPrefixPath));

    await p.npmRegistry.shutdown();

    // this won't succeed as we stopped npm registry
    await expect(p.esy(`fetch`)).rejects.toThrow();

    // this should work as we specified a path to tarballs
    await p.esy(`fetch --cache-tarballs-path ${tarballsPath}`);
  });

  test('install: it can store source tarballs in a local directory', async function() {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      helpers.packageJson({
        name: 'root',
        dependencies: {
          a: '*',
          b: '*',
        },
      }),
    );

    await p.defineNpmPackage({
      name: 'a',
      version: '1.0.0',
    });

    await p.defineNpmPackage({
      name: 'b',
      version: '2.0.0',
    });

    const tarballsPath = path.join(p.projectPath, 'sources');

    await p.esy(`install --cache-tarballs-path ${tarballsPath}`);

    await fs.exists(tarballsPath);

    // remove caches
    await fs.remove(path.join(p.projectPath, '_esy'));
    await fs.remove(path.join(p.esyPrefixPath));

    await p.npmRegistry.shutdown();

    // this won't succeed as we stopped npm registry
    await expect(p.esy(`install`)).rejects.toThrow();

    // this should work as we specified a path to tarballs
    await p.esy(`install --cache-tarballs-path ${tarballsPath}`);

    {
      const {stdout} = await p.esy(`node -p "JSON.stringify(require('a/package.json'))"`);
      expect(JSON.parse(stdout.trim())).toEqual({
        name: 'a',
        version: '1.0.0',
      });
    }
    {
      const {stdout} = await p.esy(`node -p "JSON.stringify(require('b/package.json'))"`);
      expect(JSON.parse(stdout.trim())).toEqual({
        name: 'b',
        version: '2.0.0',
      });
    }
  });

  test('it checks that cached tarballs are downloaded', async function() {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      helpers.packageJson({
        name: 'root',
        dependencies: {
          a: '*',
          b: '*',
        },
      }),
    );

    await p.defineNpmPackage({
      name: 'a',
      version: '1.0.0',
    });

    await p.defineNpmPackage({
      name: 'b',
      version: '2.0.0',
    });

    const tarballsPath = path.join(p.projectPath, 'sources');

    // perform install so that we know sources are cached already
    await p.esy(`install`);

    await p.esy(`install --cache-tarballs-path ${tarballsPath}`);
    await fs.exists(tarballsPath);

    // remove caches
    await fs.remove(path.join(p.projectPath, '_esy'));
    await fs.remove(path.join(p.esyPrefixPath));

    // shutdown npm registry so just fetch would fail
    await p.npmRegistry.shutdown();

    // this won't succeed as we stopped npm registry
    await expect(p.esy(`fetch`)).rejects.toThrow();

    // this should work as we specified a path to tarballs
    await p.esy(`fetch --cache-tarballs-path ${tarballsPath}`);
  });
});
