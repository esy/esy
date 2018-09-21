// @flow

const outdent = require('outdent');
const helpers = require('../test/helpers.js');

helpers.skipSuiteOnWindows();

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
            ["chmod" "+x" "hello.exe"]
          ]
          install: [
            ["cp" "hello.exe" "%{bin}%/hello.exe"]
          ]
        `,
      ),
      helpers.dummyExecutable('hello'),
    ];

    const p = await createTestSandbox(...fixture);
    await p.esy('install --skip-repository-update');

    // build should execute build commands from pkg.opam file
    await p.esy('build');
    const {stdout} = await p.esy('x hello.exe');
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
            ["chmod" "+x" "dep.exe"]
          ]
          install: [
            ["cp" "dep.exe" "%{bin}%/dep.exe"]
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
            ["chmod" "+x" "hello.exe"]
          ]
          install: [
            ["cp" "hello.exe" "%{bin}%/hello.exe"]
          ]
        `,
      ),
      helpers.dummyExecutable('hello'),
    ];

    const p = await createTestSandbox(...fixture);

    await p.esy('install --skip-repository-update');

    // build should execute build commands from pkg.opam file
    await p.esy('build');
    const {stdout} = await p.esy('x hello.exe');
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
    ];

    const p = await createTestSandbox(...fixture);
    await p.esy('install --skip-repository-update');

    // build shouldn't execute build commands from *.opam files
    await p.esy('build');
  });
});
