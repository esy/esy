// @flow

const {packageJson, dir, file, ocamlPackage} = require('../test/helpers');

const simpleProject = [
  packageJson({
    name: 'simple-project',
    version: '1.0.0',
    dependencies: {
      dep: '*',
    },
    devDependencies: {
      devDep: '*',
    },
    esy: {
      buildEnv: {
        root__build: 'root__build__value',
      },
      exportedEnv: {
        root__local: {val: 'root__local__value'},
        root__global: {val: 'root__global__value', scope: 'global'},
      },
    },
  }),
  dir(
    'node_modules',
    dir(
      'dep',
      packageJson({
        name: 'dep',
        version: '1.0.0',
        esy: {
          buildsInSource: true,
          build: 'ocamlopt -o #{self.root / self.name} #{self.root / self.name}.ml',
          install: 'cp #{self.root / self.name} #{self.bin / self.name}',
          exportedEnv: {
            dep__local: {val: 'dep__local__value'},
            dep__global: {val: 'dep__global__value', scope: 'global'},
          },
        },
        dependencies: {
          ocaml: '*',
          depOfDep: '*',
        },
        _resolved: '...',
      }),
      file('dep.ml', 'let () = print_endline "__dep__"'),
    ),
    dir(
      'depOfDep',
      packageJson({
        name: 'depOfDep',
        version: '1.0.0',
        esy: {
          exportedEnv: {
            depOfDep__local: {val: 'depOfDep__local__value'},
            depOfDep__global: {val: 'depOfDep__global__value', scope: 'global'},
          },
        },
        _resolved: '...',
      }),
    ),
    dir(
      'devDep',
      packageJson({
        name: 'devDep',
        version: '1.0.0',
        esy: {
          buildsInSource: true,
          build: 'ocamlopt -o #{self.root / self.name} #{self.root / self.name}.ml',
          install: 'cp #{self.root / self.name} #{self.bin / self.name}',
          exportedEnv: {
            devDep__local: {val: 'devDep__local__value'},
            devDep__global: {val: 'devDep__global__value', scope: 'global'},
          },
        },
        dependencies: {
          ocaml: '*',
        },
        _resolved: '...',
      }),
      file('devDep.ml', 'let () = print_endline "__devDep__"'),
    ),
    ocamlPackage(),
  ),
];

module.exports = {simpleProject};
