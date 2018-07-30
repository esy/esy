// @flow

const {packageJson, dir, file, ocamlPackage} = require('../test/helpers');

const simpleProject = [
  packageJson({
    "name": "simple-project",
    "version": "1.0.0",
    "dependencies": {
      "dep": "*"
    },
    "devDependencies": {
      "devDep": "*"
    },
    "esy": {},
  }),
  dir('node_modules',
    dir('dep',
      packageJson({
        "name": "dep",
        "version": "1.0.0",
        "esy": {
          "buildsInSource": true,
          "build": "ocamlopt -o #{self.root / self.name} #{self.root / self.name}.ml",
          "install": "cp #{self.root / self.name} #{self.bin / self.name}",
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
        "esy": {
          "buildsInSource": true,
          "build": "ocamlopt -o #{self.root / self.name} #{self.root / self.name}.ml",
          "install": "cp #{self.root / self.name} #{self.bin / self.name}",
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

module.exports = {simpleProject};
