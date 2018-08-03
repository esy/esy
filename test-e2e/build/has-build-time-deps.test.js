// @flow

const childProcess = require('child_process');
const path = require('path');

const outdent = require('outdent');
const {
  createTestSandbox,
  packageJson,
  dir,
  file,
  ocamlPackage,
  skipSuiteOnWindows,
} = require('../test/helpers');

skipSuiteOnWindows("Needs investigation");

const fixture = [
  packageJson({
    name: 'hasBuildTimeDeps',
    version: '1.0.0',
    esy: {
      buildsInSource: true,
      build: [
        'buildTimeDep #{self.name}.ml',
        'ocamlopt -o #{self.bin / self.name} unix.cmxa #{self.name}.ml',
      ],
    },
    dependencies: {
      dep: '*',
      ocaml: '*',
    },
    buildTimeDependencies: {
      buildTimeDep: '*',
    },
  }),
  dir(
    'node_modules',
    dir(
      'buildTimeDep',
      packageJson({
        name: 'buildTimeDep',
        version: '1.0.0',
        esy: {
          buildsInSource: true,
          build: 'ocamlopt -o #{self.bin / self.name} #{self.name}.ml',
        },
        dependencies: {
          ocaml: '*',
        },
        _resolved: '...',
      }),
      file(
        'buildTimeDep.ml',
        outdent`
        let () =
          let oc = open_out Sys.argv.(1) in
          let src = "let () = print_endline \\"Built with buildTimeDep@1.0.0\\"" in
          output_string oc src;
          close_out oc
      `,
      ),
    ),
    dir(
      'dep',
      packageJson({
        name: 'dep',
        version: '1.0.0',
        esy: {
          build: [
            'buildTimeDep #{self.name}.ml',
            'ocamlopt -o #{self.bin / self.name} unix.cmxa #{self.name}.ml',
          ],
        },
        buildTimeDependencies: {
          buildTimeDep: '*',
        },
        _resolved: '...',
      }),
      dir(
        'node_modules',
        dir(
          'buildTimeDep',
          packageJson({
            name: 'buildTimeDep',
            version: '2.0.0',
            esy: {
              buildsInSource: true,
              build: 'ocamlopt -o #{self.bin / self.name} #{self.name}.ml',
            },
            dependencies: {
              ocaml: '*',
            },
            _resolved: '...',
          }),
          file(
            'buildTimeDep.ml',
            outdent`
            let () =
              let oc = open_out Sys.argv.(1) in
              let src = "let () = print_endline \\"Built with buildTimeDep@2.0.0\\"" in
              output_string oc src;
              close_out oc
          `,
          ),
        ),
      ),
    ),
    ocamlPackage(),
  ),
];

describe('Build - has build time deps', () => {
  it('builds', async () => {
    const p = await createTestSandbox(...fixture);
    await p.esy('build');

    {
      const {stdout} = await p.esy('x hasBuildTimeDeps');
      expect(stdout).toEqual(expect.stringMatching(`Built with buildTimeDep@1.0.0`));
    }

    {
      const {stdout} = await p.esy('dep');
      expect(stdout).toEqual(expect.stringMatching(`Built with buildTimeDep@2.0.0`));
    }
  });
});
