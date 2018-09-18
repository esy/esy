// @flow

const path = require('path');
const fs = require('fs');

const {
  createTestSandbox,
  packageJson,
  file,
  dir,
  symlink,
  ocamlPackage,
  exeExtension,
} = require('../test/helpers');

function makeFixture(p) {
  return [
    packageJson({
      name: 'with-linked-dep-_build',
      version: '1.0.0',
      esy: {
        build: 'true',
      },
      dependencies: {
        dep: '*',
      },
    }),
    dir(
      'dep',
      packageJson({
        name: 'dep',
        version: '1.0.0',
        esy: {
          buildsInSource: '_build',
          build: [
            "mkdir -p #{self.root / '_build'}",
            "cp #{self.root / self.name}.ml #{self.root / '_build' / self.name}.ml",
            "ocamlopt -o #{self.root / '_build' / self.name}.exe #{self.root / '_build' / self.name}.ml",
          ],
          install: `cp #{self.root / '_build' / self.name}.exe #{self.bin / self.name}${exeExtension}`,
        },
        dependencies: {
          ocaml: '*',
        },
      }),
      file('dep.ml', 'let () = print_endline "__dep__"'),
    ),
    dir(
      'node_modules',
      dir(
        'dep',
        file(
          '_esylink',
          JSON.stringify({
            source: `link:${path.join(p.projectPath, 'dep')}`,
          }),
        ),
        symlink('package.json', '../../dep/package.json'),
      ),
      ocamlPackage(),
    ),
  ];
}

describe('Build - with linked dep _build', () => {
  it('package "dep" should be visible in all envs', async () => {
    const p = await createTestSandbox();
    await p.fixture(...makeFixture(p));
    await p.esy('build');

    const expecting = expect.stringMatching('dep');

    const dep = await p.esy('dep');
    expect(dep.stdout).toEqual(expecting);

    const b = await p.esy('b dep');
    expect(b.stdout).toEqual(expecting);

    const x = await p.esy('x dep');
    expect(x.stdout).toEqual(expecting);
  });
});
