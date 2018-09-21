// @flow

const path = require('path');

const outdent = require('outdent');
const {
  createTestSandbox,
  file,
  dir,
  packageJson,
  ocamlPackage,
  promiseExec,
  skipSuiteOnWindows,
} = require('../test/helpers');

skipSuiteOnWindows('Needs investigation');

const fixture = [
  packageJson({
    name: 'release',
    version: '0.1.0',
    license: 'MIT',
    dependencies: {
      releaseDep: '*',
      ocaml: '*',
    },
    esy: {
      buildsInSource: true,
      build: 'ocamlopt -o #{self.root / self.name} #{self.root / self.name}.ml',
      install: 'cp #{self.root / self.name} #{self.bin / self.name}',
      release: {
        releasedBinaries: ['release', 'releaseDep'],
        deleteFromBinaryRelease: ['ocaml-*'],
      },
    },
  }),
  file(
    'release.ml',
    outdent`
    let () =
      let name =
        match Sys.getenv_opt "NAME" with
        | Some name -> name
        | None -> "name"
      in
      print_endline ("RELEASE-HELLO-FROM-" ^ name)
  `,
  ),
  dir(
    'node_modules',
    dir(
      'releaseDep',
      packageJson({
        name: 'releaseDep',
        version: '0.1.0',
        esy: {
          buildsInSource: true,
          build: 'ocamlopt -o #{self.root / self.name} #{self.root / self.name}.ml',
          install: 'cp #{self.root / self.name} #{self.bin / self.name}',
        },
        dependencies: {
          ocaml: '*',
        },
      }),
      file(
        'releaseDep.ml',
        outdent`
        let () =
          print_endline "RELEASE-DEP-HELLO"
      `,
      ),
    ),
    ocamlPackage(),
  ),
];

it('Common - release', async () => {
  const p = await createTestSandbox(...fixture);

  await expect(p.esy('release')).resolves.not.toThrow();

  // npm commands are run in the _release folder
  await expect(p.npm('pack')).resolves.not.toThrow();
  await expect(p.npm('-g install ./release-*.tgz')).resolves.not.toThrow();

  await expect(
    promiseExec(path.join(p.npmPrefixPath, 'bin', 'release'), {
      env: {...process.env, NAME: 'ME'},
    }),
  ).resolves.toEqual({
    stdout: 'RELEASE-HELLO-FROM-ME\n',
    stderr: '',
  });

  await expect(
    promiseExec(path.join(p.npmPrefixPath, 'bin', 'releaseDep')),
  ).resolves.toEqual({
    stdout: 'RELEASE-DEP-HELLO\n',
    stderr: '',
  });

  // check that `release ----where` returns a path to a real `release` binary

  const releaseBinPath = (await promiseExec(
    path.join(p.npmPrefixPath, 'bin', 'release ----where'),
  )).stdout.trim();
  await expect(promiseExec(releaseBinPath)).resolves.toEqual({
    stdout: 'RELEASE-HELLO-FROM-name\n',
    stderr: '',
  });
});
