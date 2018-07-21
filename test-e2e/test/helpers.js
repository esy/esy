const path = require('path');
const fs = require('fs-extra');
const childProcess = require('child_process');
const {promisify} = require('util');

const ESYCOMMAND = require.resolve('../../bin/esy');

const promiseExec = promisify(childProcess.exec);

const esyCommands = {
  build: (cwd, testPath) =>
    promiseExec(`${ESYCOMMAND} build`, {
      cwd,
      env: {...process.env, ESY__PREFIX: testPath},
    }),
  command: (cwd, command) => promiseExec(`${ESYCOMMAND} ${command}`, {cwd}),
  b: (cwd, command) => promiseExec(`${ESYCOMMAND} b ${command}`, {cwd}),
  x: (cwd, command) => promiseExec(`${ESYCOMMAND} x ${command}`, {cwd}),
};

function initFixture(fixture) {
  return fs.mkdtemp('/tmp/esy.XXXX').then(TEST_ROOT => {
    const TEST_PROJECT = path.join(TEST_ROOT, 'project');
    const TEST_BIN = path.join(TEST_ROOT, 'bin');

    return fs
      .mkdir(TEST_BIN)
      .then(() => fs.link(ESYCOMMAND, path.join(TEST_BIN, 'esy')))
      .then(() => fs.copy(fixture, TEST_PROJECT))
      .then(() => TEST_ROOT);
  });
}

module.exports = {
  esyCommands,
  initFixture,
  promiseExec,
};
