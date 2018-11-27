// @flow

const path = require('path');
const fs = require('fs-extra');
const helpers = require('../test/helpers.js');

describe('offline installation workflow', function() {
  test('it can store source tarballs in a local directory', async function() {
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
    await fs.remove(path.join(p.esyPrefixPath, 'esyi', 'source'));

    await p.npmRegistry.shutdown();

    // this won't succeed as we stopped npm registry
    await expect(p.esy(`fetch`)).rejects.toThrow();

    // this should work as we specified a path to tarballs
    await p.esy(`fetch --cache-tarballs-path ${tarballsPath}`);
  });

  test('it can checks that cached tarballs are downloaded', async function() {
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
    await fs.remove(path.join(p.esyPrefixPath, 'esyi', 'source'));

    // shutdown npm registry so just fetch would fail
    await p.npmRegistry.shutdown();

    // this won't succeed as we stopped npm registry
    await expect(p.esy(`fetch`)).rejects.toThrow();

    // this should work as we specified a path to tarballs
    await p.esy(`fetch --cache-tarballs-path ${tarballsPath}`);
  });
});
