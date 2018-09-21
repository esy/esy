// @flow

const crypto = require('crypto');
const fs = require('fs-extra');
const os = require('os');
const path = require('path');
const childProcess = require('child_process');

const isWindows = process.platform === 'win32';
const ocamlVersion = '4.6.6';

const esyCommand =
  process.platform === 'win32'
    ? require.resolve('../_release/_build/default/esy/bin/esyCommand.exe')
    : require.resolve('../bin/esy');

function getTempDir() {
  return isWindows ? os.tmpdir() : '/tmp';
}

const esyPrefixPath = path.join(getTempDir(), crypto.randomBytes(20).toString('hex'));

function mkdir(path) {
  try {
    fs.mkdirSync(path);
  } catch (e) {
    // doesn't matter if it exists
  }
}

function mkdirTemp() {
  const p = path.join(getTempDir(), crypto.randomBytes(20).toString('hex'));
  fs.mkdirSync(p);
  return p;
}

function esy(sandboxPath /* : string */, args /* : string */) {
  return childProcess.execSync(`${esyCommand} ${args}`, {
    cwd: sandboxPath,
    env: {...process.env, ESY__PREFIX: esyPrefixPath},
    stdio: 'inherit',
  });
}

function buildOCaml() {
  const sandboxPath = mkdirTemp();

  fs.writeFileSync(
    path.join(sandboxPath, 'package.json'),
    JSON.stringify({
      name: 'root-project',
      version: '1.0.0',
      dependencies: {
        ocaml: ocamlVersion,
      },
      esy: {
        build: [],
        install: [],
      },
    }),
  );

  console.log(`*** building OCaml toolchain at ${sandboxPath} ***`);

  esy(sandboxPath, 'install');
  esy(sandboxPath, 'build');
}

function setup(_globalConfig /* : any */) {
  buildOCaml();
}

module.exports.setup = setup;
module.exports.esyPrefixPath = esyPrefixPath;
module.exports.esyCommand = esyCommand;
module.exports.esy = esy;
module.exports.isWindows = isWindows;
module.exports.mkdirTemp = mkdirTemp;
module.exports.ocamlVersion = ocamlVersion;
