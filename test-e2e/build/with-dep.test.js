// @flow

const path = require('path');
const {
  createTestSandbox,
  packageJson,
  dir,
  file,
  ocamlPackage,
  skipSuiteOnWindows,
} = require('../test/helpers');

skipSuiteOnWindows();

const fixture = [
  packageJson({
    name: 'withDep',
    version: '1.0.0',
    esy: {
      build: 'true',
    },
    dependencies: {
      dep: '*',
    },
  }),
  dir(
    'node_modules',
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
        dependencies: {
          ocaml: '*',
        },
        _resolved: '...',
      }),
      file('dep.ml', 'let () = print_endline "__dep__"'),
    ),
    ocamlPackage(),
  ),
];

describe('Build - with dep', () => {
  it('package "dep" should be visible in all envs', async () => {
    const p = await createTestSandbox(...fixture);
    await p.esy('build');

    const expecting = expect.stringMatching('__dep__');

    const dep = await p.esy('dep');
    expect(dep.stdout).toEqual(expecting);

    const b = await p.esy('b dep');
    expect(b.stdout).toEqual(expecting);

    const x = await p.esy('x dep');
    expect(x.stdout).toEqual(expecting);
  });
});
