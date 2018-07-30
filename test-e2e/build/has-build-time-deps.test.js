// @flow

const childProcess = require('child_process');
const path = require('path');

const {genFixture, packageJson, dir} = require('../test/helpers');

const fixture = [
  packageJson({
    "name": "has-build-time-deps",
    "version": "1.0.0",
    "license": "MIT",
    "esy": {
      "build": [
        [
          "bash",
          "-c",
          "echo \"#!/bin/bash\necho #{self.name} was built with:\necho $(build-time-dep)\" > #{self.target_dir / self.name}"
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
    "buildTimeDependencies": {
      "build-time-dep": "*"
    }
  }),
  dir('node_modules',
    dir('build-time-dep',
      packageJson({
        "name": "build-time-dep",
        "version": "1.0.0",
        "esy": {
          "build": [
            [
              "bash",
              "-c",
              "echo '#!/bin/bash\necho #{self.name}@#{self.version}' > #{self.target_dir / self.name}"
            ],
            "chmod +x $cur__target_dir/$cur__name"
          ],
          "install": [
            "cp $cur__target_dir/$cur__name $cur__bin/$cur__name"
          ]
        }
      })
    ),
    dir('dep',
      packageJson({
        "name": "dep",
        "version": "1.0.0",
        "esy": {
          "build": [
            [
              "bash",
              "-c",
              "echo \"#!/bin/bash\necho #{self.name} was built with:\necho $(build-time-dep)\" > #{self.target_dir / self.name}"
            ],
            "chmod +x $cur__target_dir/$cur__name"
          ],
          "install": [
            "cp $cur__target_dir/$cur__name $cur__bin/$cur__name"
          ]
        },
        "buildTimeDependencies": {
          "build-time-dep": "*"
        }
      }),
      dir('node_modules',
        dir('build-time-dep',
          packageJson({
            "name": "build-time-dep",
            "version": "2.0.0",
            "license": "MIT",
            "esy": {
              "build": [
                [
                  "bash",
                  "-c",
                  "echo '#!/bin/bash\necho #{self.name}@#{self.version}' > #{self.target_dir / self.name}"
                ],
                "chmod +x $cur__target_dir/$cur__name"
              ],
              "install": [
                "cp $cur__target_dir/$cur__name $cur__bin/$cur__name"
              ]
            }
          }),
        ),
      ),
    ),
  ),
];

describe('Build - has build time deps', () => {

  let p;

  beforeAll(async () => {
    p = await genFixture(...fixture);
    await p.esy('build');
  });

  it('x dep', async () => {
    expect.assertions(1);

    const {stdout} = await p.esy('dep');
    expect(stdout).toEqual(
      expect.stringMatching(`dep was built with:
build-time-dep@2.0.0`),
    );

  });

  it('x has-build-time-deps', async () => {
    expect.assertions(2);

    const {stdout} = await p.esy('x has-build-time-deps');
    expect(stdout).toEqual(expect.stringMatching(`has-build-time-deps was built with:`));
    expect(stdout).toEqual(expect.stringMatching(`build-time-dep@1.0.0`));
  });

  it('b build-time-dep', async () => {
    expect.assertions(1);

    const {stdout} = await p.esy('b build-time-dep');
    expect(stdout).toEqual(expect.stringMatching(`build-time-dep@1.0.0`));
  });
});
