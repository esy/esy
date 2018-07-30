// @flow

const path = require('path');
const del = require('del');
const fs = require('fs-extra');

const {genFixture, file, dir, packageJson} = require('../test/helpers');

const fixture = [
  packageJson({
    "name": "symlinks-into-dep",
    "version": "1.0.0",
    "license": "MIT",
    "esy": {
      "build": [
        "ln -s #{dep.bin / dep.name} #{self.bin / self.name}"
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
            "ln -s #{subdep.bin / subdep.name} #{self.bin / self.name}"
          ]
        },
        "dependencies": {
          "subdep": "*"
        },
        "_resolved": "http://sometarball.gz"
      }),
      dir('node_modules',
        dir('subdep',
          packageJson({
            "name": "subdep",
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
                "cp $cur__target_dir/$cur__name $cur__bin/$cur__name"
              ]
            },
            "_resolved": "http://subdep-sometarball.gz"
          })
        )
      )
    )
  )
];

it('export import build - from list', async () => {
  const p = await genFixture(...fixture);
  await p.esy('build');

  await p.esy('export-dependencies');

  const list = await fs.readdir(path.join(p.projectPath, '_export'));
  await fs.writeFile(
    path.join(p.projectPath, 'list.txt'),
    list.map(x => path.join('_export', x)).join('\n') + '\n',
  );

  const expected = [
    expect.stringMatching('dep-1.0.0'),
    expect.stringMatching('subdep-1.0.0'),
  ];

  const delResult = await del(path.join(p.esyPrefixPath, '3_*', 'i', '*'), {force: true});
  expect(delResult).toEqual(expect.arrayContaining(expected));

  await p.esy('import-build --from ./list.txt');

  const ls = await fs.readdir(path.join(p.esyPrefixPath, '/3/i'));
  expect(ls).toEqual(expect.arrayContaining(expected));
});
