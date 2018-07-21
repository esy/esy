// @flow

const {file, dir, packageJson, genFixture, promiseExec} = require('../test/helpers.js');

describe('build opam sandbox', () => {

  it('builds an opam sandbox with a single opam file', async () => {

    const p = await genFixture(
      file('opam', `
        opam-version: "1.2"
        build: [
          ["bash" "-c" "echo '#!/bin/bash\necho hello-from-opam' > %{bin}%/hello"]
          ["chmod" "+x" "%{bin}%/hello"]
        ]
        install: [
          ["true"]
        ]
      `),
      dir('node_modules',
        dir('ocaml',
          packageJson({
            name: 'ocaml',
            version: '4.6.1'
          })
        ),
        dir('@esy-ocaml',
          dir('substs',
            packageJson({
              name: '@esy-ocaml/substs',
              version: '0.0.0'
            })
          ),
          dir('esy-installer',
            packageJson({
              name: '@esy-ocaml/esy-installer',
              version: '0.0.0'
            })
          )
        )
      )
    );

    await p.esy('build');
    expect((await p.esy('x hello')).stdout).toEqual(expect.stringContaining('hello-from-opam'));
  });

  it('builds an opam sandbox with multiple opam files', async () => {

    const p = await genFixture(
      file('one.opam', `
        opam-version: "1.2"
        build: [
          ["false"]
        ]
        install: [
          ["true"]
        ]
      `),
      file('two.opam', `
        opam-version: "1.2"
        build: [
          ["false"]
        ]
        install: [
          ["true"]
        ]
      `),
      dir('node_modules',
        dir('ocaml',
          packageJson({
            name: 'ocaml',
            version: '4.6.1'
          })
        ),
        dir('@esy-ocaml',
          dir('substs',
            packageJson({
              name: '@esy-ocaml/substs',
              version: '0.0.0'
            })
          ),
          dir('esy-installer',
            packageJson({
              name: '@esy-ocaml/esy-installer',
              version: '0.0.0'
            })
          )
        )
      )
    );

    const {stderr} = await p.esy('build');
    expect(stderr).toEqual(expect.stringContaining("warn build commands from opam files won't be executed"));
  });

});
