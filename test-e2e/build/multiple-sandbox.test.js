// @flow

const helpers = require('../test/helpers.js');

const {file, dir, packageJson, exeExtension} = helpers;

helpers.skipSuiteOnWindows();

function makePackage(
  {
    name,
    dependencies = {},
    devDependencies = {},
  }: {
    name: string,
    dependencies?: {[name: string]: string},
    devDependencies?: {[name: string]: string},
  },
  ...items
) {
  return dir(
    name,
    packageJson({
      name: name,
      version: '1.0.0',
      license: 'MIT',
      esy: {
        buildsInSource: true,
        build: 'ocamlopt -o #{self.root / self.name}.exe #{self.root / self.name}.ml',
        install: `cp #{self.root / self.name}.exe #{self.bin / self.name}${exeExtension}`,
      },
      dependencies,
      devDependencies,
      '_esy.source': 'path:./',
    }),
    file(`${name}.ml`, `let () = print_endline "__${name}__"`),
    ...items,
  );
}

describe('projects with multiple sandboxes', function() {
  it('can build multiple sandboxes', async () => {
    const fixture = [
      file(
        'package.json',
        `
        {
          "esy": {},
          "dependencies": {"default-dep": "*"}
        }
        `,
      ),
      file(
        'package.custom.json',
        `
        {
          "esy": {},
          "dependencies": {"custom-dep": "*"}
        }
        `,
      ),
      dir(
        '_esy',
        dir(
          ['default', 'node_modules'],
          makePackage({name: 'default-dep', dependencies: {ocaml: '*'}}),
          helpers.ocamlPackage(),
        ),
        dir(
          ['custom', 'node_modules'],
          makePackage({name: 'custom-dep', dependencies: {ocaml: '*'}}),
          helpers.ocamlPackage(),
        ),
      ),
    ];

    const p = await helpers.createTestSandbox(...fixture);

    await p.esy('build');

    {
      const {stdout} = await p.esy('default-dep');
      expect(stdout.trim()).toBe('__default-dep__');
    }

    expect(p.esy('custom-dep')).rejects.toThrow();

    await p.esy('@custom build');

    {
      const {stdout} = await p.esy('@custom custom-dep');
      expect(stdout.trim()).toBe('__custom-dep__');
    }

    expect(p.esy('@custom default-dep')).rejects.toThrow();
  });
});
