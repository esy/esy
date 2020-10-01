// @flow


// --------------------------------------------- //
//            NOT IN USE ANYMORE
// --------------------------------------------- //


const child_process = require('child_process');
const os = require('os');
const fs = require('fs-extra');
const path = require('path');
const outdent = require('outdent');

const isWindows = os.platform() === 'win32';

const root = path.normalize(path.join(__dirname, '..'));
const bin = path.join(root, 'bin');

fs.mkdirpSync(bin);

function which(cmd) {
  const which = isWindows ? 'C:\\Windows\\System32\\WHERE' : 'which';
  return child_process
    .execSync(`${which} esy-solve-cudf`)
    .toString()
    .trim();
}

const esyBashPath = path.dirname(require.resolve('esy-bash/package.json'));
const esySolveCudf = path.dirname(require.resolve('esy-solve-cudf/package.json'));
const esySolveCudfExe = path.join(esySolveCudf, 'esySolveCudfCommand.exe');

if (isWindows) {
  const esy = path.join(bin, 'esy.cmd');
  fs.writeFileSync(
    path.join(bin, 'esy.cmd'),
    outdent`
    @ECHO off
    @SETLOCAL
    @SET ESY__SOLVE_CUDF_COMMAND=${esySolveCudfExe}
    @SET ESY__ESY_BASH=${esyBashPath}
    "${root}/_build/default/bin/esy.exe" %*
    `
  );
} else {
  const esy = path.join(bin, 'esy');
  fs.writeFileSync(
    esy,
    outdent`
    #!/bin/bash
    export ESY__SOLVE_CUDF_COMMAND="${esySolveCudfExe}"
    export ESY__ESY_BASH="${esyBashPath}"
    exec "${root}/_build/default/bin/esy.exe" "$@"
    `
  );
  fs.chmodSync(esy, 0o755);
}
