// @flow

const path = require('path');
const outdent = require('outdent');
const helpers = require('../test/helpers.js');
const {packageJson, dir} = helpers;

helpers.skipSuiteOnWindows('needs fixes for path pretty printing');

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

    const err = await expectAndReturnRejection(p.esy('install'));
    expect(err.stderr.trim()).toEqual(
      outdent`
      error: reading "dependencies": expected an object
        reading package metadata from link-dev:./package.json
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
        dependencies: {dep: 'path:./dep'},
      }),
      dir(
        'dep',
        packageJson({
          name: 'dep',
          version: '0.0.0',
          esy: {},
          dependencies: [],
        }),
      ),
    );

    const err = await expectAndReturnRejection(p.esy('install'));
    expect(err.stderr).toMatch(
      outdent`
      error: reading "dependencies": expected an object
        reading package metadata from path:dep
        resolving metadata dep@path:dep
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

    await p.esy('install');
    const err = await expectAndReturnRejection(p.esy('build'));
    expect(err.stderr).toMatch(
      outdent`
      error: command failed: 'false' (exited with 1)
      esy-build-package: exiting with errors above...
      error: build failed with exit code: 1
        
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
        dependencies: {dep: 'path:./dep'},
      }),
      dir(
        'dep',
        packageJson({
          name: 'dep',
          version: '0.0.0',
          esy: {build: 'false'},
        }),
      ),
    );

    await p.esy('install');

    const depBuildPlan = JSON.parse((await p.esy('build-plan dep@path:dep')).stdout);

    const err = await expectAndReturnRejection(p.esy('build'));
    expect(err.stderr).toMatch(
      outdent`
      error: build failed with exit code: 1
        build log:
          # esy-build-package: building: dep@path:dep
          # esy-build-package: pwd: ${depBuildPlan.sourcePath}
          # esy-build-package: running: 'false'
          error: command failed: 'false' (exited with 1)
          esy-build-package: exiting with errors above...
          
        building dep@path:dep
      esy: exiting due to errors above
      `,
    );
  });
});
