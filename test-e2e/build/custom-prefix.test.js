// @flow

const os = require('os');
const path = require('path');

const outdent = require('outdent');
const {genFixture, ocamlPackage, dir, packageJson, file, exeExtension, skipSuiteOnWindows} = require('../test/helpers');

skipSuiteOnWindows();

const fixture = [
  packageJson({
    "name": "custom-prefix",
    "version": "1.0.0",
    "esy": {
      "build": [
        "cp #{self.root /}test.ml #{self.target_dir /}test.ml",
        "ocamlopt -o #{self.target_dir / self.name}.exe #{self.target_dir /}test.ml"
      ],
      "install": `cp #{self.target_dir / self.name}.exe #{self.bin / self.name}${exeExtension}`
    },
    "dependencies": {
      "ocaml": "*"
    }
  }),
  file('.esyrc', 'esy-prefix-path: ./store'),
  file('test.ml', outdent`
    let () = print_endline "custom-prefix"
  `),
  dir('node_modules',
    ocamlPackage(),
  )
];

it('Build - custom prefix', async () => {
  const p = await genFixture(...fixture);

  await p.esy('build', {noEsyPrefix: true});

  const {stdout} = await p.esy('x custom-prefix', {noEsyPrefix: true});
  expect(stdout).toEqual('custom-prefix' + os.EOL);
});
