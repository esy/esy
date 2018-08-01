// @flow

const {
  createTestSandbox,
  packageJson,
  skipSuiteOnWindows,
  dir,
  file,
  ocamlPackage,
  ocamlPackagePath,
} = require('../test/helpers');

skipSuiteOnWindows('Needs esyi to work');

const fixture = [
  packageJson({
    name: 'default-command',
    version: '1.0.0',
    esy: {
      build: 'true',
    },
    dependencies: {
      dep: 'link:./dep',
    },
  }),
  dir(
    'dep',
    packageJson({
      name: 'dep',
      version: '1.0.0',
      esy: {
        build: [
          'cp #{self.root / self.name}.ml #{self.target_dir / self.name}.ml',
          'ocamlopt -o #{self.target_dir / self.name} #{self.target_dir / self.name}.ml',
        ],
        install: 'cp #{self.target_dir / self.name} #{self.bin / self.name}',
      },
      _resolved: '...',
      dependencies: {
        ocaml: `link:${ocamlPackagePath}`,
      },
    }),
    file('dep.ml', 'let () = print_endline "__dep__"'),
  ),
];

it('Build - default command', async () => {
  let p = await createTestSandbox(...fixture);
  await p.esy();

  const dep = await p.esy('dep');

  expect(dep.stdout.trim()).toEqual('__dep__');
});
