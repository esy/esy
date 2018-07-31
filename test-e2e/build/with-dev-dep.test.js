// @flow

const path = require('path');
const {genFixture, packageJson, dir, file, ocamlPackage, exeExtension, skipSuiteOnWindows} = require('../test/helpers');

skipSuiteOnWindows();

const fixture = [
  packageJson({
    "name": "with-dev-dep",
    "version": "1.0.0",
    "esy": {
      "build": "true"
    },
    "dependencies": {
      "dep": "*"
    },
    "devDependencies": {
      "devDep": "*"
    }
  }),
  dir('node_modules',
    dir('dep',
      packageJson({
        "name": "dep",
        "version": "1.0.0",
        "esy": {
          "buildsInSource": true,
          "build": "ocamlopt -o #{self.root / self.name}.exe #{self.root / self.name}.ml",
          "install": `cp #{self.root / self.name}.exe #{self.bin / self.name}${exeExtension}`
        },
        "dependencies": {
          "ocaml": "*"
        },
        "_resolved": "..."
      }),
      file('dep.ml', 'let () = print_endline "__dep__"'),
    ),
    dir('devDep',
      packageJson({
        "name": "devDep",
        "version": "1.0.0",
        "license": "MIT",
        "esy": {
          "buildsInSource": true,
          "build": "ocamlopt -o #{self.root / self.name}.exe #{self.root / self.name}.ml",
          "install": `cp #{self.root / self.name}.exe #{self.bin / self.name}${exeExtension}`
        },
        "dependencies": {
          "ocaml": "*"
        },
        "_resolved": "..."
      }),
      file('devDep.ml', 'let () = print_endline "__devDep__"'),
    ),
    ocamlPackage(),
  )
];

describe('Build - with dev dep', () => {

  let p;

  beforeEach(async () => {
    p = await genFixture(...fixture);
    await p.esy('build');
  });

  it('package "dep" should be visible in all envs', async () => {
    const expecting = expect.stringMatching('__dep__');

    const dep = await p.esy('dep');
    expect(dep.stdout).toEqual(expecting);

    const bDep = await p.esy('b dep');
    expect(bDep.stdout).toEqual(expecting);

    const xDep = await p.esy('x dep');
    expect(xDep.stdout).toEqual(expecting);
  });

  it('package "dev-dep" should be visible only in command env', async () => {
    const expecting = expect.stringMatching('__devDep__');

    const dep = await p.esy('devDep');
    expect(dep.stdout).toEqual(expecting);

    const xDep = await p.esy('x devDep');
    expect(xDep.stdout).toEqual(expecting);

    return expect(p.esy('b devDep')).rejects.toThrow();
  });
});
