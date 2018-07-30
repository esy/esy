// @flow

const path = require('path');

const {genFixture, packageJson, dir, file, ocamlPackage} = require('../test/helpers');

const fixture = [
  packageJson({
    "name": "augment-path",
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
        "license": "MIT",
        "esy": {
          "buildsInSource": true,
          "build": "ocamlopt -o #{self.lib/}dep #{self.root/}dep.ml",
          "exportedEnv": {
            "PATH": {
              "val": "#{self.lib : $PATH}",
              "scope": "global"
            }
          }
        },
        "dependencies": {
          "ocaml": "*"
        },
        "_resolved": "http://sometarball.gz"
      }),
      file('dep.ml', 'let () = print_endline "__DEP__"'),
    ),
    ocamlPackage(),
  )
];

describe('Build - augment path', () => {
  it('package "dep" should be visible in all envs', async () => {
    expect.assertions(3);

    const p = await genFixture(...fixture);
    await p.esy('build');

    const expecting = expect.stringMatching('__DEP__');

    const dep = await p.esy('dep');
    expect(dep.stdout).toEqual(expecting);

    const b = await p.esy('b dep');
    expect(b.stdout).toEqual(expecting);

    const x = await p.esy('x dep');
    expect(x.stdout).toEqual(expecting);
  });
});
