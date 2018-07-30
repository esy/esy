// @flow

const path = require('path');

const outdent = require('outdent');
const {genFixture, file, dir, packageJson, ocamlPackage, promiseExec} = require('../test/helpers');

const fixture = [
  packageJson({
    "name": "release",
    "version": "0.1.0",
    "license": "MIT",
    "dependencies": {
      "release-dep": "link:./dependencies/release-dep",
      "ocaml": "*"
    },
    "esy": {
      "build": [
        ["cp", "#{self.name '.exe'}", "#{self.bin / self.name '.exe'}"],
        ["chmod", "+x", "#{self.bin / self.name '.exe'}"]
      ],
      "release": {
        "releasedBinaries": ["release.exe", "release-dep.exe"],
        "deleteFromBinaryRelease": ["ocaml-*"]
      }
    }
  }),
  file('release.exe', outdent`
    #!/bin/bash

    echo "RELEASE-HELLO-FROM-$NAME"
  `),
  dir('node_modules',
    dir('release-dep',
      packageJson({
        "name": "release-dep",
        "version": "0.1.0",
        "esy": {
          "build": [
            [
              "cp",
              "#{self.name '.exe'}",
              "#{self.bin / self.name '.exe'}"
            ],
            [
              "chmod",
              "+x",
              "#{self.bin / self.name '.exe'}"
            ]
          ],
          "release": {
            "releasedBinaries": [
              "release-dep.exe"
            ]
          }
        }
      }),
      file('release-dep.exe', outdent`
        #!/bin/bash

        echo RELEASE-DEP-HELLO
      `)
    ),
    ocamlPackage()
  )
];

it('Common - release', async () => {
  jest.setTimeout(300000);

  const p = await genFixture(...fixture);

  await expect(p.esy('release')).resolves.not.toThrow();

  // npm commands are run in the _release folder
  await expect(p.npm('pack')).resolves.not.toThrow();
  await expect(p.npm('-g install ./release-*.tgz')).resolves.not.toThrow();

  await expect(
    promiseExec(path.join(p.npmPrefixPath, 'bin', 'release.exe'), {
      env: {...process.env, NAME: 'ME'},
    }),
  ).resolves.toEqual({
    stdout: 'RELEASE-HELLO-FROM-ME\n',
    stderr: '',
  });

  await expect(
    promiseExec(path.join(p.npmPrefixPath, 'bin', 'release-dep.exe')),
  ).resolves.toEqual({
    stdout: 'RELEASE-DEP-HELLO\n',
    stderr: '',
  });
});
