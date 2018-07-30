// @flow

const path = require('path');

const {genFixture, packageJson, dir} = require('../test/helpers');

const fixture = [
  packageJson({
    "name": "creates-symlinks",
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
        "cp $cur__target_dir/$cur__name $cur__lib/$cur__name",
        "ln -s $cur__lib/$cur__name $cur__bin/$cur__name"
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
            "cp $cur__target_dir/$cur__name $cur__lib/$cur__name",
            "ln -s $cur__lib/$cur__name $cur__bin/$cur__name"
          ]
        },
        "_resolved": "http://sometarball.gz"
      })
    )
  )
];

it('Build - creates symlinks', async () => {
  expect.assertions(4);
  const p = await genFixture(...fixture);

  await p.esy('build');

  const expecting = expect.stringMatching('dep');

  const dep = await p.esy('dep');
  expect(dep.stdout).toEqual(expecting);
  const bDep = await p.esy('b dep');
  expect(bDep.stdout).toEqual(expecting);
  const xDep = await p.esy('x dep');
  expect(xDep.stdout).toEqual(expecting);

  let x = await p.esy('x creates-symlinks');
  expect(x.stdout).toEqual(expect.stringMatching('creates-symlinks'));
});
