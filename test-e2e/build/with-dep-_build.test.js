// @flow

const path = require('path');
const {genFixture, packageJson, dir} = require('../test/helpers');

const fixture = [
  packageJson({
    "name": "with-dep-_build",
    "version": "1.0.0",
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
        "esy": {
          "buildsInSource": "_build",
          "build": [
            "mkdir _build",
            [
              "bash",
              "-c",
              "echo \"#!/bin/bash\necho $cur__name\" > ./_build/$cur__name"
            ],
            "chmod +x ./_build/$cur__name"
          ],
          "install": [
            "cp ./_build/$cur__name $cur__bin/$cur__name"
          ]
        },
        "_resolved": "http://sometarball.gz"
      })
    )
  )
]

describe('Build - with dep _build', () => {

  let p;

  beforeAll(async () => {
    p = await genFixture(...fixture);
    await p.esy('build');
  });

  it('package "dep" should be visible in all envs', async () => {
    expect.assertions(3);

    const expecting = expect.stringMatching('dep');

    const dep = await p.esy('dep');
    expect(dep.stdout).toEqual(expecting);
    const b = await p.esy('b dep');
    expect(b.stdout).toEqual(expecting);
    const x = await p.esy('x dep');
    expect(x.stdout).toEqual(expecting);
  });

  it('with-dep-_build', async () => {
    expect.assertions(1);

    const {stdout} = await p.esy('x with-dep-_build');
    expect(stdout).toEqual(expect.stringMatching('with-dep-_build'));
  });
});
