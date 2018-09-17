// @flow

const outdent = require('outdent');
const helpers = require('../test/helpers.js');

const {file, dir, packageJson} = helpers;

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

  it('turning a dir into esy package', async () => {
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
        resolutions: {
          dep: {
            source: 'path:./dep',
            override: {
              build: [
                'cp dep.ml #{self.target_dir/}dep.ml',
                'ocamlopt -o #{self.target_dir/}dep.exe #{self.target_dir/}dep.ml',
              ],
              install: ['cp #{self.target_dir/}dep.exe #{self.bin/}dep.exe'],
              dependencies: {
                ocaml: '*',
              },
            },
          },
        },
      }),
      dir('dep', file('dep.ml', 'print_endline "__dep__"')),
    ];
    const p = await createTestSandbox(...fixture);

    await p.esy('install --skip-repository-update');
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

  it('turning a linked dir into esy package', async () => {
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
        resolutions: {
          dep: {
            source: 'link:./dep',
            override: {
              build: [
                'cp dep.ml #{self.target_dir/}dep.ml',
                'ocamlopt -o #{self.target_dir/}dep.exe #{self.target_dir/}dep.ml',
              ],
              install: ['cp #{self.target_dir/}dep.exe #{self.bin/}dep.exe'],
              dependencies: {
                ocaml: '*',
              },
            },
          },
        },
      }),
      dir('dep', file('dep.ml', 'print_endline "__dep__"')),
    ];
    const p = await createTestSandbox(...fixture);

    await p.esy('install --skip-repository-update');
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
