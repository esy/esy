// @flow

const path = require('path');

const outdent = require('outdent');
const {genFixture, ocamlPackage, dir, packageJson, file} = require('../test/helpers');

const fixture = [
  packageJson({
    "name": "custom-prefix",
    "version": "1.0.0",
    "license": "MIT",
    "esy": {
      "build": [
        [
          "cp",
          "#{self.original_root /}test.ml",
          "#{self.target_dir /}test.ml"
        ],
        [
          "ocamlopt",
          "-o",
          "#{self.target_dir / self.name}.exe",
          "#{self.target_dir /}test.ml"
        ]
      ],
      "install": [
        [
          "cp",
          "#{self.target_dir / self.name}.exe",
          "#{self.bin / self.name}"
        ]
      ]
    },
    "dependencies": {
      "ocaml": "*"
    }
  }),
  file('test.ml', outdent`
    let () = print_endline "custom-prefix"
  `),
  dir('node_modules',
    ocamlPackage(),
  )
];

it('Build - custom prefix', async () => {
  jest.setTimeout(200000);
  expect.assertions(1);
  const p = await genFixture(...fixture);

  await p.esy('install', {noEsyPrefix: true});
  await p.esy('build', {noEsyPrefix: true});

  const {stdout} = await p.esy('x custom-prefix', {noEsyPrefix: true});
  expect(stdout).toEqual('custom-prefix\n');
});
