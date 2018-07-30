// @flow

const {packageJson, dir} = require('../test/helpers');

const simpleProject = [
  packageJson({
    "name": "simple-project",
    "version": "1.0.0",
    "dependencies": {
      "dep": "*"
    },
    "devDependencies": {
      "dev-dep": "*"
    },
    "esy": {},
  }),
  dir('node_modules',
    dir('dep',
      packageJson({
        "name": "dep",
        "version": "1.0.0",
        "esy": {
          "build": [
            [
              "bash",
              "-c",
              "echo '#!/bin/bash\necho #{self.name}' > #{self.install / 'bin' / self.name}"
            ],
            [
              "chmod",
              "+x",
              "#{self.install / 'bin' / self.name}"
            ]
          ]
        },
        "_resolved": "dep"
      })
    ),
    dir('dev-dep',
      packageJson({
        "name": "dev-dep",
        "version": "1.0.0",
        "esy": {
          "build": [
            [
              "bash",
              "-c",
              "echo '#!/bin/bash\necho #{self.name}' > #{self.install / 'bin' / self.name}"
            ],
            [
              "chmod",
              "+x",
              "#{self.install / 'bin' / self.name}"
            ]
          ]
        },
        "_resolved": "dev-dep"
      })
    ),
  )
];

module.exports = {simpleProject};
