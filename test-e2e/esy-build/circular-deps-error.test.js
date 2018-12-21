// @flow

const path = require('path');
const outdent = require('outdent');
const helpers = require('../test/helpers');

function makeFixture(p) {
  return [
    helpers.packageJson({
      name: 'hasCircularDeps',
      version: '1.0.0',
      esy: {
        build: 'true',
      },
      dependencies: {
        dep: 'path:./dep',
      },
    }),
    helpers.dir(
      'dep',
      helpers.packageJson({
        name: 'dep',
        version: '1.0.0',
        esy: {
          build: 'true',
        },
        dependencies: {
          depOfDep: 'path:../depOfDep',
        },
      }),
    ),
    helpers.dir(
      'depOfDep',
      helpers.packageJson({
        name: 'depOfDep',
        version: '1.0.0',
        esy: {
          build: 'true',
        },
        dependencies: {
          dep: 'path:../dep',
        },
      }),
    ),
  ];
}

describe(`'esy build' command: circular dependency error`, () => {
  test('it prints a nice error message', async () => {
    const p = await helpers.createTestSandbox();
    await p.fixture(...makeFixture(p));
    await p.esy('install');
    await expect(p.esy('build')).rejects.toMatchObject({
      stderr: outdent`
        info esy build ${helpers.esyVersion} (using package.json)
        error: found circular dependency on: dep@path:dep
          processing depOfDep@path:depOfDep
          processing dep@path:dep
          processing hasCircularDeps@link:./package.json
          creating task for hasCircularDeps@link:./package.json
        esy: exiting due to errors above

      `,
    });
  });
});
