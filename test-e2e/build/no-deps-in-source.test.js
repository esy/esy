// @flow

const path = require('path');
const outdent = require('outdent');
const {
  createTestSandbox,
  ocamlPackage,
  dir,
  file,
  packageJson,
  exeExtension,
} = require('../test/helpers');

const fixture = [
  packageJson({
    name: 'no-deps-in-source',
    version: '1.0.0',
    license: 'MIT',
    esy: {
      buildsInSource: true,
      build: [['ocamlopt', '-o', '#{self.name}.exe', 'test.ml']],
      install: [`cp ./$cur__name.exe $cur__bin/$cur__name${exeExtension}`],
    },
    dependencies: {
      ocaml: 'esy-ocaml/ocaml#6aacc05',
    },
  }),
  file(
    'test.ml',
    outdent`
    let () = print_endline "no-deps-in-source"
  `,
  ),
  dir('node_modules', ocamlPackage()),
];

it('Build - no deps in source', async () => {
  const p = await createTestSandbox(...fixture);
  await p.esy('build');

  const {stdout} = await p.esy('x no-deps-in-source');
  expect(stdout.trim()).toEqual('no-deps-in-source');
});
