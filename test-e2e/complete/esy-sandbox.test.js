// @flow

const outdent = require('outdent');
const helpers = require('../test/helpers.js');

const {file, packageJson} = helpers;

helpers.skipSuiteOnWindows();

describe('complete workflow for esy sandboxes', () => {
  async function createTestSandbox(...fixture) {
    const p = await helpers.createTestSandbox(...fixture);

    // add ocaml package, required by opam sandboxes implicitly
    await p.defineNpmPackageOfFixture(helpers.ocamlPackage().items);

    // add @esy-ocaml/substs package, required by opam sandboxes implicitly
    await p.defineNpmPackage({
      name: '@esy-ocaml/substs',
      version: '1.0.0',
      esy: {},
    });

    return p;
  }

  it('no dependencies', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {
          build: ['true'],
        },
      }),
    ];
    const p = await createTestSandbox(...fixture);
    await p.esy('install');
    await p.esy('build');
  });

  it('no package name, no package version', async () => {
    const fixture = [
      packageJson({
        esy: {
          build: [
            'cp root.ml #{self.target_dir/}root.ml',
            'ocamlopt -o #{self.target_dir/}root.exe #{self.target_dir/}root.ml',
          ],
          install: ['cp #{self.target_dir/}root.exe #{self.bin/}root.exe'],
        },
        dependencies: {
          ocaml: '*',
        },
        devDependencies: {
          ocaml: '*',
        },
      }),
      file('root.ml', 'print_endline "__root__"'),
    ];
    const p = await createTestSandbox(...fixture);
    await p.esy('install');
    await p.esy('build');
    const {stdout} = await p.esy('x root.exe');
    expect(stdout.trim()).toEqual('__root__');
  });

  it('no dependencies, only ocaml devDep', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {
          build: [
            'cp root.ml #{self.target_dir/}root.ml',
            'ocamlopt -o #{self.target_dir/}root.exe #{self.target_dir/}root.ml',
          ],
          install: ['cp #{self.target_dir/}root.exe #{self.bin/}root.exe'],
        },
        dependencies: {
          ocaml: '*',
        },
        devDependencies: {
          ocaml: '*',
        },
      }),
      file('root.ml', 'print_endline "__root__"'),
    ];
    const p = await createTestSandbox(...fixture);
    await p.esy('install');
    await p.esy('build');
    const {stdout} = await p.esy('x root.exe');
    expect(stdout.trim()).toEqual('__root__');
  });

  it('npm dependencies, only ocaml devDep', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {
          ocaml: '*',
          dep: '*',
        },
        devDependencies: {
          ocaml: '*',
        },
      }),
    ];
    const p = await createTestSandbox(...fixture);

    await p.defineNpmPackageOfFixture([
      packageJson({
        name: 'dep',
        version: '1.0.0',
        esy: {
          build: [
            'cp dep.ml #{self.target_dir/}dep.ml',
            'ocamlopt -o #{self.target_dir/}dep.exe #{self.target_dir/}dep.ml',
          ],
          install: ['cp #{self.target_dir/}dep.exe #{self.bin/}dep.exe'],
        },
        dependencies: {
          ocaml: '*',
        },
      }),
      file('dep.ml', 'print_endline "__dep__"'),
    ]);

    await p.esy('install');
    await p.esy('build');

    {
      const {stdout} = await p.esy('dep.exe');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('b dep.exe');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('x dep.exe');
      expect(stdout.trim()).toEqual('__dep__');
    }
  });

  it('opam dependencies, only ocaml devDep', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {
          ocaml: '*',
          '@opam/dep': '*',
        },
        devDependencies: {
          ocaml: '*',
        },
      }),
    ];
    const p = await createTestSandbox(...fixture);

    await p.defineOpamPackageOfFixture(
      {
        name: 'dep',
        version: '1',
        opam: outdent`
          opam-version: "1.2"
          build: [
            ["ocamlopt" "-o" "dep.exe" "dep.ml"]
          ]
          install: [
            ["cp" "dep.exe" "%{bin}%/dep.exe"]
          ]
        `,
        url: null,
      },
      [
        helpers.file(
          'dep.ml',
          outdent`
            let () = print_endline "__dep__"
          `,
        ),
      ],
    );

    await p.esy('install');
    await p.esy('build');

    {
      const {stdout} = await p.esy('dep.exe');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('b dep.exe');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('x dep.exe');
      expect(stdout.trim()).toEqual('__dep__');
    }
  });
});
