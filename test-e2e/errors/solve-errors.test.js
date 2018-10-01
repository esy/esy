// @flow

const outdent = require('outdent');
const helpers = require('../test/helpers.js');
const {packageJson, file, dir} = helpers;

helpers.skipSuiteOnWindows('needs fixes for path pretty printing');

type ChildProcessError = {
  stderr: string,
};

function expectAndReturnRejection(p): Promise<ChildProcessError> {
  return (p.then(() => expect(true).toBe(false), err => err): any);
}

describe('"esy solve" errors', function() {
  it('reports errors about conflict', async () => {
    const p = await helpers.createTestSandbox();

    await p.defineNpmPackage({
      name: 'conflict',
      version: '1.0.0',
      esy: {},
    });

    await p.defineNpmPackage({
      name: 'conflict',
      version: '2.0.0',
      esy: {},
    });

    await p.fixture(
      packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          dep: './dep',
          conflict: '2.0.0',
        },
      }),
      dir(
        'dep',
        packageJson({
          name: 'dep',
          esy: {},
          dependencies: {
            conflict: '1.0.0',
          },
        }),
      ),
    );

    const err = await expectAndReturnRejection(p.esy('install --skip-repository-update'));
    expect(err.stderr.trim()).toEqual(
      outdent`
      error: No solution found:
     
      Conflicting constraints:
        root -> dep -> conflict@=1.0.0
        root -> conflict@=2.0.0
     
        
      esy: exiting due to errors above
      `,
    );
  });

  it('reports errors about conflict (one side is opam package)', async () => {
    const p = await helpers.createTestSandbox();

    await p.defineNpmPackage({
      name: '@esy-ocaml/substs',
      version: '1.0.0',
      esy: {},
    });

    await p.defineOpamPackage({
      name: 'conflict',
      version: '1.0.0',
      opam: outdent`
        opam-version: "2.0"
      `,
      url: null,
    });

    await p.defineOpamPackage({
      name: 'conflict',
      version: '2.0.0',
      opam: outdent`
        opam-version: "2.0"
      `,
      url: null,
    });

    await p.fixture(
      packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          dep: 'path:./dep/dep.opam',
          '@opam/conflict': '2.0.0',
        },
      }),
      dir(
        'dep',
        file(
          'dep.opam',
          outdent`
          opam-version: "2.0"
          depends: [
            "conflict" {< "2.0.0"}
          ]
          `,
        ),
      ),
    );

    const err = await expectAndReturnRejection(p.esy('install --skip-repository-update'));
    expect(err.stderr.trim()).toEqual(
      outdent`
      error: No solution found:

      Conflicting constraints:
        root -> dep -> @opam/conflict@<opam:2.0.0
        root -> @opam/conflict@=opam:2.0.0

        
      esy: exiting due to errors above
      `,
    );
  });

  it('reports errors about missing opam packages (no matching packages)', async () => {
    const p = await helpers.createTestSandbox();

    await p.defineNpmPackage({
      name: '@esy-ocaml/substs',
      version: '1.0.0',
      esy: {},
    });

    await p.defineOpamPackage({
      name: 'missing',
      version: '1.0.0',
      opam: outdent`
        opam-version: "2.0"
      `,
      url: null,
    });

    await p.fixture(
      packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          dep: 'path:./dep/dep.opam',
          '@opam/missing': '1.0.0',
        },
      }),
      dir(
        'dep',
        file(
          'dep.opam',
          outdent`
          opam-version: "2.0"
          depends: [
            "missing" {> "1.0.0"}
          ]
          `,
        ),
      ),
    );

    const err = await expectAndReturnRejection(p.esy('install --skip-repository-update'));
    expect(err.stderr.trim()).toEqual(
      outdent`
      error: No solution found:

      No package matching:
     
        root -> dep -> @opam/missing@>opam:1.0.0
        
        Versions available:
        
          @opam/missing@opam:1.0.0
     
        
      esy: exiting due to errors above
      `,
    );
  });

  it('reports errors about missing opam packages (no such package exists)', async () => {
    const p = await helpers.createTestSandbox();

    await p.defineNpmPackage({
      name: '@esy-ocaml/substs',
      version: '1.0.0',
      esy: {},
    });

    await p.fixture(
      packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          dep: 'path:./dep/dep.opam',
          '@opam/missing': '1.0.0',
        },
      }),
      dir(
        'dep',
        file(
          'dep.opam',
          outdent`
          opam-version: "2.0"
          depends: [
            "missing" {> "1.0.0"}
          ]
          `,
        ),
      ),
    );

    const err = await expectAndReturnRejection(p.esy('install --skip-repository-update'));
    expect(err.stderr.trim()).toEqual(
      outdent`
      error: No solution found:

      No package matching:
     
        root -> dep -> @opam/missing@>opam:1.0.0
        
     
        
      esy: exiting due to errors above
      `,
    );
  });

  it('reports errors about missing npm packages (no matching packages)', async () => {
    const p = await helpers.createTestSandbox();

    await p.defineOpamPackage({
      name: 'missing',
      version: '1.0.0',
      opam: outdent`
        opam-version: "2.0"
      `,
      url: null,
    });

    await p.fixture(
      packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          missing: '>1.0.0',
        },
      }),
    );

    const err = await expectAndReturnRejection(p.esy('install --skip-repository-update'));
    expect(err.stderr.trim()).toEqual(
      outdent`
      error: No solution found:

      No package matching:
     
        root -> missing@>1.0.0
        

        resolving request missing@>1.0.0
      esy: exiting due to errors above
      `,
    );
  });

  it('reports errors about missing npm packages (no such package exist)', async () => {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          missing: '>1.0.0',
        },
      }),
    );

    const err = await expectAndReturnRejection(p.esy('install --skip-repository-update'));
    expect(err.stderr.trim()).toEqual(
      outdent`
      error: No solution found:

      No package matching:
     
        root -> missing@>1.0.0
        

        resolving request missing@>1.0.0
      esy: exiting due to errors above
      `,
    );
  });
});
