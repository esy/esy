// @flow

const {setup: setup_, createSandbox, mkdirTemp, ocamlVersion} = require('../setup.js');
const path = require('path');
const childProcess = require('child_process');

function setup() {
  setup_();

  const npmPrefix = mkdirTemp();
  const sandbox = createSandbox();

  console.log(`*** Release test at ${sandbox.path} ***`);

  function npm(cwd /*:string*/, cmd /*:string*/) {
    console.log(`EXEC: npm ${cmd}`);
    // make sure we run npm w/o pnp
    const PATH = path.dirname(process.argv0) + path.delimiter + process.env.PATH;
    return childProcess.execSync(`npm ${cmd}`, {
      cwd,
      env: {...process.env, PATH, NPM_CONFIG_PREFIX: npmPrefix},
      stdio: 'inherit',
    });
  }

  return {sandbox, npmPrefix, npm};
}

module.exports = {setup};
