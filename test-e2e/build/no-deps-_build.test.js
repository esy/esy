// @flow

const path = require('path');
const outdent = require('outdent');
const {genFixture, ocamlPackage, dir, file, packageJson} = require('../test/helpers');

const fixture = [
  packageJson({
    "name": "no-deps-_build",
    "version": "1.0.0",
    "license": "MIT",
    "esy": {
      "buildsInSource": "_build",
      "build": [
        "mkdir -p _build",
        [
          "cp",
          "#{self.original_root /}test.ml",
          "./_build/test.ml"
        ],
        [
          "ocamlopt",
          "-o",
          "./_build#{/ self.name}.exe",
          "./_build/test.ml"
        ]
      ],
      "install": [
        "cp ./_build/#{self.name}.exe $cur__bin/$cur__name"
      ]
    },
    "dependencies": {
      "ocaml": "*"
    }
  }),
  file('test.ml', outdent`
    let () = print_endline "no-deps-_build"
  `),
  dir('node_modules', ocamlPackage())
];

it('Build - no deps _build', async () => {
  const p = await genFixture(...fixture);

  await p.esy('build');

  const {stdout} = await p.esy('x no-deps-_build');
  expect(stdout).toEqual('no-deps-_build\n');
});
