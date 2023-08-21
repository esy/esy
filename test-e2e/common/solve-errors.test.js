// @flow

const outdent = require('outdent');
const helpers = require('../test/helpers.js');
const exec = require('../test/exec.js');

const {packageJson, file, dir} = helpers;
let version = exec.exec('git describe --tags').trim();
helpers.skipSuiteOnWindows('needs fixes for path pretty printing');

type ChildProcessError = {
  stderr: string,
};

function expectAndReturnRejection(p): Promise<ChildProcessError> {
  return (p.then(
    () => expect(true).toBe(false),
    (err) => err,
  ): any);
}

describe('"esy solve" errors', function () {
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
      info install ${version} (using package.json)
      info resolving esy packages: done
      info solving esy constraints: done
      error: No solution found:
     
      Conflicting constraints:
        root -> dep -> conflict@=1.0.0
        root -> conflict@=2.0.0
     
        
      esy: exiting due to errors above
      `,
    );
  });

  it('reports errors about conflict (path and path)', async () => {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          dep: './dep',
          conflict: 'path:./conflict',
        },
      }),
      dir(
        'dep',
        packageJson({
          name: 'dep',
          esy: {},
          dependencies: {
            conflict: 'path:../conflict-other',
          },
        }),
      ),
      dir('conflict', helpers.packageJson({esy: {}})),
      dir('conflict-other', helpers.packageJson({esy: {}})),
    );

    const err = await expectAndReturnRejection(p.esy('install --skip-repository-update'));
    expect(err.stderr.trim()).toEqual(
      outdent`
      info install ${version} (using package.json)
      info resolving esy packages: done
      info solving esy constraints: done
      error: No solution found:
     
      Conflicting constraints:
        root -> conflict@path:conflict
        root -> dep -> conflict@path:conflict-other
     
        
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
      info install ${version} (using package.json)
      info resolving esy packages: done
      info solving esy constraints: done
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
      info install ${version} (using package.json)
      info resolving esy packages: done
      info solving esy constraints: done
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
      info install ${version} (using package.json)
      info resolving esy packages: done
      info solving esy constraints: done
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
      info install ${version} (using package.json)
      info resolving esy packages: done
      info solving esy constraints: done
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
      info install ${version} (using package.json)
      info resolving esy packages: done
      info solving esy constraints: done
      error: No solution found:

      No package matching:
     
        root -> missing@>1.0.0
        

        resolving request missing@>1.0.0
      esy: exiting due to errors above
      `,
    );
  });

  it('reports errors about missing path: packages (path does not exist)', async () => {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          missing: 'path:./missing',
        },
      }),
    );

    const err = await expectAndReturnRejection(p.esy('install --skip-repository-update'));
    expect(err.stderr.trim()).toEqual(
      outdent`
      info install ${version} (using package.json)
      error: path 'missing' does not exist
        resolving missing@path:missing
      esy: exiting due to errors above
      `,
    );
  });
});

describe('"resolutions" misconfiguration errors', function () {
  it('plain resolution', async function () {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          pkg: '*',
        },
        resolutions: {
          pkg: 'github:author/pkg',
        },
      }),
    );
    const err = await expectAndReturnRejection(p.esy('install --skip-repository-update'));
    expect(err.stderr.trim()).toEqual(
      outdent`
      error: parsing "github:author/pkg": <author>/<repo>(:<manifest>)?#<commit>: missing or incorrect <commit>
        reading package metadata from link-dev:./package.json
        loading root package metadata
      esy: exiting due to errors above
      `,
    );
  });

  it('resolution w/ override', async function () {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          pkg: '*',
        },
        resolutions: {
          pkg: {
            source: 'author/pkg#ref',
            override: {
              build: ['true'],
            },
          },
        },
      }),
    );
    const err = await expectAndReturnRejection(p.esy('install --skip-repository-update'));
    expect(err.stderr.trim()).toEqual(
      outdent`
      error: parsing "author/pkg#ref": <author>/<repo>(:<manifest>)?#<commit>: missing or incorrect <commit>
        reading package metadata from link-dev:./package.json
        loading root package metadata
      esy: exiting due to errors above
      `,
    );
  });

  it('link to a non-existent path', async function () {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          pkg: '*',
        },
        resolutions: {
          pkg: 'link:./somepath/pkg',
        },
      }),
    );
    const err = await expectAndReturnRejection(p.esy('install --skip-repository-update'));
    expect(err.stderr.trim()).toEqual(
      outdent`
      info install ${version} (using package.json)
      error: somepath/pkg doesn't exist
        reading package metadata from link:somepath/pkg
      esy: exiting due to errors above
      `,
    );
  });

  it('link to a non-existent manifest', async function () {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          pkg: '*',
        },
        resolutions: {
          pkg: 'link:./somepath/some.json',
        },
      }),
      dir('somepath', packageJson({name: 'some'})),
    );
    const err = await expectAndReturnRejection(p.esy('install --skip-repository-update'));
    expect(err.stderr.trim()).toEqual(
      outdent`
      info install ${version} (using package.json)
      error: unable to read manifests from some.json
        reading package metadata from link:somepath/some.json
      esy: exiting due to errors above
      `,
    );
  });
});
