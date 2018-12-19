// @flow

const {createSandbox, mkdirTemp, ocamlVersion} = require('../setup.js');
const FixtureUtils = require('../../test-e2e/test/FixtureUtils.js');
const {dir, file, packageJson} = FixtureUtils;
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const outdent = require('outdent');
const childProcess = require('child_process');

const {setup, isWindows} = require('./setup.js');
const {npmPrefix, sandbox, npm, exec} = setup();

console.log(`*** Release test at ${sandbox.path} ***`);

FixtureUtils.initializeSync(sandbox.path, [
  packageJson({
    name: 'release',
    version: '0.1.0',
    license: 'MIT',
    dependencies: {
      releaseDep: './releaseDep',
      ocaml: ocamlVersion,
    },
    esy: {
      buildsInSource: true,
      build: 'ocamlopt -o #{self.root / self.name}.exe #{self.root / self.name}.ml',
      install: 'cp #{self.root / self.name}.exe #{self.bin / self.name}.exe',
      exportedEnv: {
        'some.var': {val: 'some.val', scope: 'global'},
        'some"var': {val: 'some"val', scope: 'global'},
      },
      release: {
        bin: {
          r: 'release.exe',
          rd: 'releaseDep.exe',
        },
        includePackages: ['release', 'releaseDep'],
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
    'releaseDep',
    packageJson({
      name: 'releaseDep',
      version: '0.1.0',
      esy: {
        buildsInSource: true,
        build: 'ocamlopt -o #{self.root / self.name}.exe #{self.root / self.name}.ml',
        install: 'cp #{self.root / self.name}.exe #{self.bin / self.name}.exe',
      },
      dependencies: {
        ocaml: ocamlVersion,
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
]);

sandbox.esy('install');
sandbox.esy('npm-release');

const releasePath = path.join(sandbox.path, '_release');

npm(releasePath, 'pack');
npm(releasePath, '-g install ./release-0.1.0.tgz');

if (!isWindows) {
  const stdout = exec(path.join(npmPrefix, 'bin', 'r'), {
    env: {
      ...process.env,
      NAME: 'ME',
    },
  });
  assert.equal(stdout.toString(), 'RELEASE-HELLO-FROM-ME\n');
} else {
  const stdout = exec(path.join(npmPrefix, 'r.cmd'), {
    env: {
      ...process.env,
      NAME: 'ME',
    },
  });
  assert.equal(stdout.toString(), 'RELEASE-HELLO-FROM-ME\r\n');
}

if (!isWindows) {
  const stdout = exec(path.join(npmPrefix, 'bin', 'rd'));
  assert.equal(stdout.toString(), 'RELEASE-DEP-HELLO\n');
} else {
  const stdout = exec(path.join(npmPrefix, 'rd.cmd'));
  assert.equal(stdout.toString(), 'RELEASE-DEP-HELLO\r\n');
}

// check that `release ----where` returns a path to a real `release` binary

if (!isWindows) {
  const releaseBin = exec(path.join(npmPrefix, 'bin', 'r') + ' ----where');
  const stdout = exec(releaseBin.toString());
  assert.equal(stdout.toString(), 'RELEASE-HELLO-FROM-name\n');
} else {
  const releaseBin = exec(path.join(npmPrefix, 'r.cmd') + ' ----where');
  const stdout = exec(releaseBin.toString());
  assert.equal(stdout.toString(), 'RELEASE-HELLO-FROM-name\r\n');
}
