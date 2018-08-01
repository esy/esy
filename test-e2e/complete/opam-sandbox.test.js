// @flow

const outdent = require('outdent');
const helpers = require('../test/helpers.js');

helpers.skipSuiteOnWindows();

describe('installing dependencies for opam sandbox', () => {
  async function createTestSandbox(...fixture) {
    const p = await helpers.createTestSandbox(...fixture);

    // add ocaml package, required by opam sandboxes implicitly
    await p.defineNpmPackageOfFixture(helpers.ocamlPackage().items);

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
            ["ocamlopt" "-o" "hello.exe" "hello.ml"]
          ]
          install: [
            ["cp" "hello.exe" "%{bin}%/hello.exe"]
          ]
        `,
      ),
      helpers.file(
        'hello.ml',
        outdent`
          let () = print_endline "__opam__"
        `,
      ),
    ];

    const p = await createTestSandbox(...fixture);
    await p.esy('install --skip-repository-update');

    // build should execute build commands from pkg.opam file
    await p.esy('build');
    const {stdout} = await p.esy('x hello.exe');
    expect(stdout.trim()).toEqual('__opam__');
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
            ["ocamlopt" "-o" "dep.exe" "dep.ml"]
          ]
          install: [
            ["cp" "dep.exe" "%{bin}%/dep.exe"]
          ]
        `,
        url: null,
      },
      [
        helpers.file(
          'dep.ml',
          outdent`
            let () = print_endline "__dep__"
          `,
        ),
      ],
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
    const {stdout} = await p.esy('dep.exe');
    expect(stdout.trim()).toEqual('__dep__');
  });

  it('single <pkg>.opam file', async () => {
    const fixture = [
      helpers.file(
        'pkg.opam',
        outdent`
          opam-version: "1.2"
          build: [
            ["ocamlopt" "-o" "hello.exe" "hello.ml"]
          ]
          install: [
            ["cp" "hello.exe" "%{bin}%/hello.exe"]
          ]
        `,
      ),
      helpers.file(
        'hello.ml',
        outdent`
          let () = print_endline "__opam__"
        `,
      ),
    ];

    const p = await createTestSandbox(...fixture);

    await p.esy('install --skip-repository-update');

    // build should execute build commands from pkg.opam file
    await p.esy('build');
    const {stdout} = await p.esy('x hello.exe');
    expect(stdout.trim()).toEqual('__opam__');
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
            ["false"]
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
            ["false"]
          ]
        `,
      ),
      helpers.file(
        'hello.ml',
        outdent`
          let () = print_endline "__opam__"
        `,
      ),
    ];

    const p = await createTestSandbox(...fixture);
    await p.esy('install --skip-repository-update');

    // build shouldn't execute build commands from *.opam files
    await p.esy('build');

    // we should be able to use ocaml and build stuff
    await p.esy('build ocamlopt -o hello.exe ./hello.ml');
    const {stdout} = await p.esy('./hello.exe');
    expect(stdout.trim()).toEqual('__opam__');
  });
});
