/* @flow */

const tests = require('./setup');

describe('Testing integrity of downloaded packages', function() {
  test(
    `it should fail on corrupted tarballs`,
    tests.makeTemporaryEnv(
      {
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {dep: `1.0.0`},
      },
      async ({path, run, source}) => {
        await tests.definePackage(
          {
            name: 'dep',
            version: '1.0.0',
            esy: {},
            dependencies: {},
          },
          {shasum: 'dummy-invalid-shasum'},
        );

        try {
          await run(`install`);
        } catch (err) {
          expect(/sha1 checksum mismatch/.exec(err)).toBeTruthy();
        }
      },
    ),
  );
});
