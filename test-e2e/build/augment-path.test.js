// @flow

const path = require('path');

const {genFixture, packageJson, dir} = require('../test/helpers');

const fixture = [
  packageJson({
    "name": "augment-path",
    "version": "1.0.0",
    "esy": {
      "build": [
        [
          "bash",
          "-c",
          "echo '#!/bin/bash\necho #{self.name}' > #{self.target_dir / self.name}"
        ],
        "chmod +x $cur__target_dir/$cur__name"
      ],
      "install": [
        "cp $cur__target_dir/$cur__name $cur__bin/$cur__name"
      ]
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
          "build": [
            [
              "bash",
              "-c",
              "echo \"#!/bin/bash\necho $cur__name\" > $cur__target_dir/$cur__name"
            ],
            "chmod +x $cur__target_dir/$cur__name"
          ],
          "install": [
            "cp $cur__target_dir/$cur__name $cur__install/lib"
          ],
          "exportedEnv": {
            "PATH": {
              "val": "#{self.lib : $PATH}",
              "scope": "global"
            }
          }
        },
        "_resolved": "http://sometarball.gz"
      })
    )
  )
];

describe('Build - augment path', () => {
  it('package "dep" should be visible in all envs', async () => {
    expect.assertions(3);

    const p = await genFixture(...fixture);
    await p.esy('build');

    const expecting = expect.stringMatching('dep');

    const dep = await p.esy('dep');
    expect(dep.stdout).toEqual(expecting);

    const b = await p.esy('b dep');
    expect(b.stdout).toEqual(expecting);

    const x = await p.esy('x dep');
    expect(x.stdout).toEqual(expecting);
  });
});
