// @flow

const path = require('path');
const {genFixture, packageJson, dir, file, ocamlPackage} = require('../test/helpers');

const fixture = [
  packageJson({
    "name": "with-dep-_build",
    "version": "1.0.0",
    "esy": {
      "build": "true"
    },
    "dependencies": {
      "dep": "*"
    }
  }),
  dir('node_modules',
    dir('dep',
      packageJson({
        "name": "dep",
        "version": "1.0.0",
        "esy": {
          "buildsInSource": "_build",
          "build": [
            "mkdir #{self.root / '_build'}",
            "cp #{self.root / self.name}.ml #{self.root / '_build' / self.name}.ml",
            "ocamlopt -o #{self.root / '_build' / self.name} #{self.root / '_build' / self.name}.ml",
          ],
          "install": "cp #{self.root / '_build' / self.name} #{self.bin / self.name}"
        },
        "dependencies": {
          "ocaml": "*"
        },
        "_resolved": "..."
      }),
      file('dep.ml', 'let () = print_endline "__dep__"'),
    ),
    ocamlPackage(),
  )
]

describe('Build - with dep _build', () => {

  it('package "dep" should be visible in all envs', async () => {
    const p = await genFixture(...fixture);
    await p.esy('build');

    const expecting = expect.stringMatching('__dep__');

    const dep = await p.esy('dep');
    expect(dep.stdout).toEqual(expecting);
    const b = await p.esy('b dep');
    expect(b.stdout).toEqual(expecting);
    const x = await p.esy('x dep');
    expect(x.stdout).toEqual(expecting);
  });
});
