// @flow

const path = require('path');
const fs = require('fs');
const {promisify} = require('util');
const open = promisify(fs.open);
const close = promisify(fs.close);

const {genFixture, packageJson, dir, file, symlink} = require('../test/helpers');

const fixture = [
  packageJson({
    "name": "with-linked-dep",
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
    "dependencies": {
      "dep": "*"
    }
  }),
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

describe('Build - with linked dep', () => {
  let p;

  beforeAll(async () => {
    p = await genFixture(...fixture);
    await p.esy('build');
  });

  it('package "dep" should be visible in all envs', async () => {
    expect.assertions(4);

    const dep = await p.esy('dep');
    const b = await p.esy('b dep');
    const x = await p.esy('x dep');

    const expecting = expect.stringMatching('dep');

    expect(x.stdout).toEqual(expecting);
    expect(b.stdout).toEqual(expecting);
    expect(dep.stdout).toEqual(expecting);

    const {stdout} = await p.esy('x with-linked-dep');
    expect(stdout).toEqual(expect.stringMatching('with-linked-dep'));
  });

  it('should not rebuild dep with no changes', async done => {
    expect.assertions(1);

    const noOpBuild = await p.esy('build');
    expect(noOpBuild.stdout).not.toEqual(
      expect.stringMatching('Building dep@1.0.0: starting'),
    );

    done();
  });

  it('should rebuild if file has been added', async () => {
    expect.assertions(1);

    await open(path.join(p.projectPath, 'dep', 'dummy'), 'w').then(close);

    const rebuild = await p.esy('build');
    // TODO: why is this on stderr?
    expect(rebuild.stderr).toEqual(expect.stringMatching('Building dep@1.0.0: starting'));
  });
});
