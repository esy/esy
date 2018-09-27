// @flow

const outdent = require('outdent');
const helpers = require('../test/helpers.js');
const {packageJson, dir} = helpers;

type ChildProcessError = {
  stderr: string,
};

function expectAndReturnRejection(p): Promise<ChildProcessError> {
  return (p.then(() => expect(true).toBe(false), err => err): any);
}

describe('build errors', function() {
  it('reports errors in metadata of a root package', async () => {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      packageJson({
        name: 'root',
        esy: {},
        dependencies: [],
      }),
    );

    const err = await expectAndReturnRejection(p.esy('build'));
    expect(err.stderr.trim()).toEqual(
      outdent`
      error: expected object
        reading package metadata from path:./package.json
        loading root package metadata
      esy: exiting due to errors above
      `,
    );
  });

  it('reports errors in metadata of a dependency', async () => {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      packageJson({
        name: 'root',
        esy: {},
        dependencies: {dep: '*'},
      }),
      dir(
        'node_modules',
        dir(
          'dep',
          packageJson({
            name: 'dep',
            version: '0.0.0',
            esy: {},
            dependencies: [],
          }),
        ),
      ),
    );

    const err = await expectAndReturnRejection(p.esy('build'));
    expect(err.stderr).toMatch(
      outdent`
      error: invalid package dep: error: expected object
        reading package metadata from node_modules/dep
        loading root package metadata
        processing package: root@0.0.0
      esy: exiting due to errors above
      `,
    );
  });

  it('reports errors in root builds', async () => {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      packageJson({
        name: 'root',
        esy: {build: 'false'},
      }),
    );

    const err = await expectAndReturnRejection(p.esy('build'));
    expect(err.stderr).toMatch(
      outdent`
      error: command failed: 'false'
      esy-build-package: exiting with errors above...
      error: build failed
        building root@0.0.0
      esy: exiting due to errors above
      `,
    );
  });

  it('reports errors in dependency builds', async () => {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      packageJson({
        name: 'root',
        esy: {},
        dependencies: {dep: '*'},
      }),
      dir(
        'node_modules',
        dir(
          'dep',
          packageJson({
            name: 'dep',
            version: '0.0.0',
            esy: {build: 'false'},
          }),
        ),
      ),
    );

    const err = await expectAndReturnRejection(p.esy('build'));
    expect(err.stderr).toMatch(
      outdent`
      error: build failed
        build log:
          # esy-build-package: building: dep@0.0.0
          # esy-build-package: running: 'false'
          error: command failed: 'false'
          esy-build-package: exiting with errors above...
          
        building dep@0.0.0
      esy: exiting due to errors above
      `,
    );
  });

  it('reports errors about unknown dependencies', async () => {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      packageJson({
        name: 'root',
        esy: {build: 'true'},
        dependencies: {
          'some-unknown-dependency': '*',
        },
      }),
    );

    const err = await expectAndReturnRejection(p.esy('install'));
    expect(err.stderr).toMatch(
      outdent`
      error: no npm package some-unknown-dependency found
        resolving some-unknown-dependency@*
      esy: exiting due to errors above
      `,
    );
  });

  it('reports errors about unknown dependencies (nested case)', async () => {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      packageJson({
        name: 'root',
        esy: {build: 'true'},
        dependencies: {
          dep: 'path:./dep',
        },
      }),
      dir(
        'dep',
        packageJson({
          name: 'dep',
          version: '0.0.0',
          esy: {build: 'true'},
          dependencies: {
            'some-unknown-dependency': '*',
          },
        }),
      ),
    );

    const err = await expectAndReturnRejection(p.esy('install'));
    expect(err.stderr).toMatch(
      outdent`
      error: no npm package some-unknown-dependency found
        resolving some-unknown-dependency@*
        resolving dep@path:dep
      esy: exiting due to errors above
      `,
    );
  });
});
