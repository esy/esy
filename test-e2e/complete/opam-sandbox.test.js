// @flow

const outdent = require('outdent');
const helpers = require('../test/helpers.js');

describe('complete flow for opam sandboxes', () => {
  async function createTestSandbox(...fixture) {
    const p = await helpers.createTestSandbox(...fixture);

    // add ocaml package, required by opam sandboxes implicitly
    await p.defineNpmPackage({
      name: 'ocaml',
      version: '1.0.0',
      esy: {},
    });

    // add @esy-ocaml/substs package, required by opam sandboxes implicitly
    await p.defineNpmPackage({
      name: '@esy-ocaml/substs',
      version: '1.0.0',
      esy: {},
    });

    return p;
  }

  it('single opam file, no dependencies', async () => {
    const fixture = [
      helpers.file(
        'opam',
        outdent`
          opam-version: "1.2"
          build: [
            ${helpers.buildCommandInOpam('hello.js')}
          ]
          install: [
            ["cp" "hello.cmd" "%{bin}%/hello.cmd"]
            ["cp" "hello.js" "%{bin}%/hello.js"]
          ]
        `,
      ),
      helpers.dummyExecutable('hello'),
    ];

    const p = await createTestSandbox(...fixture);
    await p.esy('install --skip-repository-update');

    // build should execute build commands from pkg.opam file
    await p.esy('build');
    const {stdout} = await p.esy('x hello.cmd');
    expect(stdout.trim()).toEqual('__hello__');
  });

  it('single opam file, has dependencies', async () => {
    const fixture = [
      helpers.file(
        'opam',
        outdent`
          opam-version: "1.2"
          depends: [
            "dep1"
            "dep2"
          ]
        `,
      ),
    ];

    const p = await createTestSandbox(...fixture);

    await p.defineOpamPackageOfFixture(
      {
        name: 'dep1',
        version: '1',
        opam: outdent`
          opam-version: "1.2"
          build: [
            ${helpers.buildCommandInOpam('dep.js')}
          ]
          install: [
            ["cp" "dep.cmd" "%{bin}%/dep.cmd"]
            ["cp" "dep.js" "%{bin}%/dep.js"]
          ]
        `,
        url: null,
      },
      [helpers.dummyExecutable('dep')],
    );

    await p.defineOpamPackage({
      name: 'dep2',
      version: '2',
      opam: outdent`
        opam-version: "1.2"
        build: [
          ["true"]
        ]
      `,
      url: null,
    });

    await p.esy('install --skip-repository-update');
    await p.esy('build');
    const {stdout} = await p.esy('dep.cmd');
    expect(stdout.trim()).toEqual('__dep__');
  });

  it('single <pkg>.opam file', async () => {
    const fixture = [
      helpers.file(
        'pkg.opam',
        outdent`
          opam-version: "1.2"
          build: [
            ${helpers.buildCommandInOpam('hello.js')}
          ]
          install: [
            ["cp" "hello.cmd" "%{bin}%/hello.cmd"]
            ["cp" "hello.js" "%{bin}%/hello.js"]
          ]
        `,
      ),
      helpers.dummyExecutable('hello'),
    ];

    const p = await createTestSandbox(...fixture);

    await p.esy('install --skip-repository-update');

    // build should execute build commands from pkg.opam file
    await p.esy('build');
    const {stdout} = await p.esy('x hello.cmd');
    expect(stdout.trim()).toEqual('__hello__');
  });

  it('multiple <pkg>.opam files', async () => {
    const fixture = [
      // this define "false" as build command to make sure esy doesn't execute
      // it
      helpers.file(
        'one.opam',
        outdent`
          opam-version: "1.2"
          build: [
            ["true"]
          ]
          depends: [
            "ocaml"
          ]
        `,
      ),
      // this define "false" as build command to make sure esy doesn't execute
      // it
      helpers.file(
        'another.opam',
        outdent`
          opam-version: "1.2"
          build: [
            ["true"]
          ]
          depends: [
            "ocaml"
          ]
        `,
      ),
    ];

    const p = await createTestSandbox(...fixture);
    await p.esy('install --skip-repository-update');
    await p.esy('build');
  });

  it('ocaml constraints should be translated to npm versions (root)', async () => {
    const p = await createTestSandbox();

    await p.fixture(
      helpers.file(
        'pkg.opam',
        outdent`
        opam-version: "2.0"
        build: [
          ["true"]
        ]
        depends: [
          "ocaml" { >= "4.07.1" & < "4.08"}
        ]
        `,
      ),
    );

    await p.defineNpmPackage({
      name: 'ocaml',
      version: '4.7.7',
      esy: {},
    });

    await p.defineNpmPackage({
      name: 'ocaml',
      version: '4.7.1005',
      esy: {},
    });
    p;
    await p.defineNpmPackage({
      name: 'ocaml',
      version: '4.8.0',
      esy: {},
    });

    await p.esy('install --skip-repository-update');

    expect(await helpers.readInstalledPackages(p.projectPath, 'pkg')).toMatchObject({
      name: 'pkg',
      dependencies: {
        ocaml: {
          name: 'ocaml',
          version: '4.7.1005',
        },
      },
    });
  });

  it('ocaml constraints should be translated to npm versions (dep)', async () => {
    const p = await createTestSandbox();

    await p.fixture(
      helpers.file(
        'pkg.opam',
        outdent`
        opam-version: "2.0"
        build: [
          ["true"]
        ]
        depends: [
          "dep"
        ]
        `,
      ),
    );

    await p.defineOpamPackage({
      name: 'dep',
      version: '1.0.0',
      opam: outdent`
        opam-version: "2.0"
        name: "dep"
        version: "1.0.0"
        build: [
          ["true"]
        ]
        depends: [
          "ocaml" { >= "4.07.1" & < "4.08"}
        ]
      `,
      url: null,
    });

    await p.defineNpmPackage({
      name: 'ocaml',
      version: '4.7.7',
      esy: {},
    });

    await p.defineNpmPackage({
      name: 'ocaml',
      version: '4.7.1005',
      esy: {},
    });
    p;
    await p.defineNpmPackage({
      name: 'ocaml',
      version: '4.8.0',
      esy: {},
    });

    await p.esy('install --skip-repository-update');

    expect(await helpers.readInstalledPackages(p.projectPath, 'pkg')).toMatchObject({
      name: 'pkg',
      dependencies: {
        '@opam/dep': {
          name: '@opam/dep',
          version: 'opam:1.0.0',
          dependencies: {
            ocaml: {
              name: 'ocaml',
              version: '4.7.1005',
            },
          },
        },
      },
    });
  });
});
