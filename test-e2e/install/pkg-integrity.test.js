/* @flow */

const helpers = require('../test/helpers.js');

describe('Testing integrity of downloaded packages', function() {
  test(`it should fail on corrupted tarballs`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {dep: `1.0.0`},
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.defineNpmPackage(
      {
        name: 'dep',
        version: '1.0.0',
        esy: {},
        dependencies: {},
      },
      {shasum: 'abc123'},
    );

    try {
      await p.esy(`install`);
    } catch (err) {
      expect(/sha1 checksum mismatch/.exec(err)).toBeTruthy();
    }
  });
});
