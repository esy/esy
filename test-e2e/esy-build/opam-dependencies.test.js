// @flow

const outdent = require('outdent');
const helpers = require('../test/helpers.js');

helpers.skipSuiteOnWindows();

describe('build projects with opam dependencies', () => {
  it('builds a project with an opam dep which refernces ocaml:* variables', async () => {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      helpers.packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          '@opam/pkg': '*',
        },
      }),
    );

    await p.defineNpmPackage({
      name: '@esy-ocaml/substs',
      version: '0.0.0',
      esy: {},
    });

    await p.defineNpmPackage({
      name: 'ocaml',
      version: '1.0.0',
      esy: {},
    });

    await p.defineOpamPackageOfFixture(
      {
        name: 'pkg',
        version: '1.0.0',
        opam: outdent`
          opam-version: "2.0"
          patches: [
            "false" {ocaml:version != "1.0.0"}
          ]
          depends: [
            "ocaml"
          ]
          build: [
            ${helpers.buildCommandInOpam('hello.js')}
            ["cp" "hello.cmd" "%{bin}%/hello.cmd"]
            ["cp" "hello.js" "%{bin}%/hello.js"]
          ]
        `,
      },
      [helpers.dummyExecutable('hello')],
    );

    await p.esy('install');
    await p.esy('build');

    {
      const {stdout} = await p.esy('x hello.cmd');
      expect(stdout.trim()).toEqual('__hello__');
    }
  });
});
