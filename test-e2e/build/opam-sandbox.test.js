// @flow

const {
  file,
  dir,
  packageJson,
  genFixture,
  promiseExec,
  ocamlPackage,
  skipSuiteOnWindows,
} = require('../test/helpers.js');

skipSuiteOnWindows();

describe('build opam sandbox', () => {
  it('builds an opam sandbox with a single opam file', async () => {
    const p = await genFixture(
      file(
        'opam',
        `
        opam-version: "1.2"
        build: [
          ["ocamlopt" "-o" "%{bin}%/hello" "hello.ml"]
        ]
      `,
      ),
      file('hello.ml', 'let () = print_endline "__hello__"'),
      dir(
        'node_modules',
        ocamlPackage(),
        dir(
          '@esy-ocaml',
          dir(
            'substs',
            packageJson({
              name: '@esy-ocaml/substs',
              version: '0.0.0',
            }),
          ),
        ),
      ),
    );

    await p.esy('build');
    expect((await p.esy('x hello')).stdout).toEqual(expect.stringContaining('__hello__'));
  });

  it('builds an opam sandbox with multiple opam files', async () => {
    const p = await genFixture(
      file(
        'one.opam',
        `
        opam-version: "1.2"
        build: [
          ["false"]
        ]
        install: [
          ["true"]
        ]
      `,
      ),
      file(
        'two.opam',
        `
        opam-version: "1.2"
        build: [
          ["false"]
        ]
        install: [
          ["true"]
        ]
      `,
      ),
      dir(
        'node_modules',
        ocamlPackage(),
        dir(
          '@esy-ocaml',
          dir(
            'substs',
            packageJson({
              name: '@esy-ocaml/substs',
              version: '0.0.0',
            }),
          ),
        ),
      ),
    );

    const {stderr} = await p.esy('build');
    expect(stderr).toEqual(
      expect.stringContaining("warn build commands from opam files won't be executed"),
    );
  });
});
