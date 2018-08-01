// @flow

const path = require('path');

const {
  createTestSandbox,
  packageJson,
  dir,
  file,
  ocamlPackage,
  exeExtension,
  skipSuiteOnWindows,
} = require('../test/helpers');

skipSuiteOnWindows();

const fixture = [
  packageJson({
    name: 'creates-symlinks',
    version: '1.0.0',
    esy: {
      buildsInSource: true,
      build: 'ocamlopt -o #{self.lib / self.name}.exe #{self.root / self.name}.ml',
      install: `ln -s #{self.lib / self.name}.exe #{self.bin / self.name}${exeExtension}`,
    },
    dependencies: {
      dep: '*',
      ocaml: '*',
    },
  }),
  file('creates-symlinks.ml', 'let () = print_endline "__creates-symlinks__"'),
  dir(
    'node_modules',
    dir(
      'dep',
      packageJson({
        name: 'dep',
        version: '1.0.0',
        license: 'MIT',
        esy: {
          buildsInSource: true,
          build: 'ocamlopt -o #{self.lib / self.name}.exe #{self.root / self.name}.ml',
          install: `ln -s #{self.lib / self.name}.exe #{self.bin / self.name}${exeExtension}`,
        },
        dependencies: {
          ocaml: '*',
        },
        _resolved: 'http://sometarball.gz',
      }),
      file('dep.ml', 'let () = print_endline "__dep__"'),
    ),
    ocamlPackage(),
  ),
];

it('Build - creates symlinks', async () => {
  expect.assertions(4);
  const p = await createTestSandbox(...fixture);

  await p.esy('build');

  const expecting = expect.stringMatching('__dep__');

  const dep = await p.esy('dep');
  expect(dep.stdout).toEqual(expecting);
  const bDep = await p.esy('b dep');
  expect(bDep.stdout).toEqual(expecting);
  const xDep = await p.esy('x dep');
  expect(xDep.stdout).toEqual(expecting);

  let x = await p.esy('x creates-symlinks');
  expect(x.stdout).toEqual(expect.stringMatching('__creates-symlinks__'));
});
