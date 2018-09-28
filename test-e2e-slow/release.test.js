// @flow

const {setup, createSandbox, mkdirTemp, ocamlVersion} = require('./setup.js');
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const outdent = require('outdent');
const childProcess = require('child_process');

setup();

const npmPrefix = mkdirTemp();
const sandbox = createSandbox();

console.log(`*** Release test at ${sandbox.path} ***`);

function npm(cwd, cmd) {
  return childProcess.execSync(`npm ${cmd}`, {
    cwd,
    env: {...process.env, NPM_CONFIG_PREFIX: npmPrefix},
    stdio: 'inherit',
  });
}

fs.writeFileSync(
  path.join(sandbox.path, 'package.json'),
  JSON.stringify({
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
      release: {
        releasedBinaries: ['release.exe', 'releaseDep.exe'],
        deleteFromBinaryRelease: ['ocaml-*'],
      },
    },
  }),
);

fs.writeFileSync(
  path.join(sandbox.path, 'release.ml'),
  outdent`
    let () =
      let name =
        match Sys.getenv_opt "NAME" with
        | Some name -> name
        | None -> "name"
      in
      print_endline ("RELEASE-HELLO-FROM-" ^ name)
  `,
);

fs.mkdirSync(path.join(sandbox.path, 'releaseDep'));

fs.writeFileSync(
  path.join(sandbox.path, 'releaseDep', 'package.json'),
  JSON.stringify({
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
);

fs.writeFileSync(
  path.join(sandbox.path, 'releaseDep', 'releaseDep.ml'),
  outdent`
    let () =
      print_endline "RELEASE-DEP-HELLO"
  `,
);

sandbox.esy('install');
sandbox.esy('release');

const releasePath = path.join(sandbox.path, '_release');

npm(releasePath, 'pack');
npm(releasePath, '-g install ./release-*.tgz');

{
  const stdout = childProcess.execSync(path.join(npmPrefix, 'bin', 'release.exe'), {
    env: {
      ...process.env,
      NAME: 'ME',
    },
  });
  assert.equal(stdout.toString(), 'RELEASE-HELLO-FROM-ME\n');
}

{
  const stdout = childProcess.execSync(path.join(npmPrefix, 'bin', 'releaseDep.exe'));
  assert.equal(stdout.toString(), 'RELEASE-DEP-HELLO\n');
}

// check that `release ----where` returns a path to a real `release` binary

{
  const releaseBin = childProcess.execSync(
    path.join(npmPrefix, 'bin', 'release.exe ----where'),
  );
  const stdout = childProcess.execSync(releaseBin.toString());
  assert.equal(stdout.toString(), 'RELEASE-HELLO-FROM-name\n');
}
