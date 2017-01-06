const fs = require('fs');
const path = require('path');
const {spawnSync} = require('child_process');
const outdent = require('outdent');

const SHELL = '/bin/bash';

function createTestEnv({sandbox, esyTest = true}) {
  function exec(cmd) {
    return spawnSync(outdent`
      set -euo pipefail
      ${esyTest ? 'export ESY__TEST="yes"' : ''}
      export ESY__STORE="${sandbox}/_esy_store"
      cd ${sandbox}
      ${cmd}
    `.trim(), {shell: SHELL});
  }
  return {
    exec(cmd) {
      let proc = exec(cmd);
      if (proc.status != 0) {
        throw new Error(outdent`
          Error while running command.

          COMMAND:

          ${cmd}
          STDOUT:

          ${proc.stdout.toString()}
          STDERR:

          ${proc.stderr.toString()}

        `);
      }
      return proc;
    },
    execAndExpectFailure(cmd) {
      return exec(cmd);
    },
    readFile(...filename) {
      filename = path.join(sandbox, ...filename);
      return fs.readFileSync(filename, 'utf8').trim();
    },
  };
}

module.exports = {createTestEnv};
