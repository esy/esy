// @flow

const {packageJson, dir, file, dummyExecutable} = require('../test/helpers');

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
    ['_esy', 'default', 'node_modules'],
    dir(
      'dep',
      packageJson({
        name: 'dep',
        version: '1.0.0',
        esy: {
          install: [
            'cp #{self.root / self.name}.exe #{self.bin / self.name}.exe',
            'chmod +x #{self.bin / self.name}.exe',
          ],
          exportedEnv: {
            dep__local: {val: 'dep__local__value'},
            dep__global: {val: 'dep__global__value', scope: 'global'},
          },
        },
        dependencies: {
          depOfDep: '*',
        },
      }),

      file('_esylink', JSON.stringify({source: `path:.`})),
      dummyExecutable('dep'),
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
      }),
      file('_esylink', JSON.stringify({source: `path:.`})),
    ),
    dir(
      'devDep',
      packageJson({
        name: 'devDep',
        version: '1.0.0',
        esy: {
          install: [
            'cp #{self.root / self.name}.exe #{self.bin / self.name}.exe',
            'chmod +x #{self.bin / self.name}.exe',
          ],
          exportedEnv: {
            devDep__local: {val: 'devDep__local__value'},
            devDep__global: {val: 'devDep__global__value', scope: 'global'},
          },
        },
      }),
      file('_esylink', JSON.stringify({source: `path:.`})),
      dummyExecutable('devDep'),
    ),
  ),
];

module.exports = {simpleProject};
