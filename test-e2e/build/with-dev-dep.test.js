// @flow

const path = require('path');

const {genFixture, packageJson, dir} = require('../test/helpers');

const fixture = [
  packageJson({
    "name": "with-dev-dep",
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
    },
    "devDependencies": {
      "dev-dep": "*"
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
              "echo '#!/bin/bash\necho #{self.name}' > #{self.target_dir / self.name}"
            ],
            "chmod +x $cur__target_dir/$cur__name"
          ],
          "install": [
            "cp $cur__target_dir/$cur__name $cur__bin/$cur__name"
          ]
        },
        "_resolved": "http://sometarball.gz"
      })
    ),
    dir('dev-dep',
      packageJson({
        "name": "dev-dep",
        "version": "1.0.0",
        "license": "MIT",
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
        "_resolved": "http://sometarball.gz"
      })
    ),
  )
];

describe('Build - with dev dep', () => {

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

    const bDep = await p.esy('b dep');
    expect(bDep.stdout).toEqual(expecting);

    const xDep = await p.esy('x dep');
    expect(xDep.stdout).toEqual(expecting);
  });

  it('package "dev-dep" should be visible only in command env', async () => {
    expect.assertions(4);

    const expecting = expect.stringMatching('dev-dep');

    const dep = await p.esy('dev-dep');
    expect(dep.stdout).toEqual(expecting);

    const xDep = await p.esy('x dev-dep');
    expect(xDep.stdout).toEqual(expecting);

    const {stdout} = await p.esy('x with-dev-dep');
    expect(stdout).toEqual(expect.stringMatching('with-dev-dep'));

    return expect(p.esy('b dev-dep')).rejects.toThrow();
  });
});
