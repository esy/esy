// @flow

const path = require('path');
const fs = require('fs');

const {genFixture, packageJson, file, dir, symlink} = require('../test/helpers');

const fixture = [
  packageJson({
    "name": "with-linked-dep-_build",
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
  dir('dep',
    packageJson({
      "name": "dep",
      "version": "1.0.0",
      "esy": {
        "buildsInSource": "_build",
        "build": [
          "mkdir -p _build",
          [
            "bash",
            "-c",
            "echo '#!/bin/bash\necho $cur__name' > _build/$cur__name"
          ],
          "chmod +x _build/$cur__name"
        ],
        "install": [
          "cp _build/$cur__name $cur__bin/$cur__name"
        ]
      },
      "dependencies": {}
    })
  ),
  dir('node_modules',
    dir('dep',
      file('_esylink', './dep'),
      symlink('package.json', '../../dep/package.json')
    ),
  ),
];

describe('Build - with linked dep _build',  () => {

  it('package "dep" should be visible in all envs', async () => {
    expect.assertions(4);

    const p = await genFixture(...fixture);
    await p.esy('build');

    const expecting = expect.stringMatching('dep');

    const dep = await p.esy('dep');
    expect(dep.stdout).toEqual(expecting);

    const b = await p.esy('b dep');
    expect(b.stdout).toEqual(expecting);

    const x = await p.esy('x dep');
    expect(x.stdout).toEqual(expecting);


    const {stdout} = await p.esy('x with-linked-dep-_build');
    expect(stdout).toEqual(expect.stringMatching('with-linked-dep-_build'));
  });
});
