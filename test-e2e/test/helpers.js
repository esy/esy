// @flow

const path = require('path');
const fs = require('fs-extra');
const childProcess = require('child_process');
const {promisify} = require('util');
const promiseExec = promisify(childProcess.exec);

const ESYCOMMAND = require.resolve('../../bin/esy');

async function initFixture(fixture: string) {
  const rootPath = await fs.mkdtemp('/tmp/esy.XXXX');
  const projectPath = path.join(rootPath, 'project');
  const binPath = path.join(rootPath, 'bin');
  const esyPrefixPath = path.join(rootPath, 'esy');

  await fs.mkdir(binPath);
  await fs.link(ESYCOMMAND, path.join(binPath, 'esy'));
  await fs.copy(fixture, projectPath);

  function esy(args: string, options: ?{noEsyPrefix?: bool}) {
    options = options || {};
    let env = process.env;
    if (!options.noEsyPrefix) {
      env = {...process.env, ESY__PREFIX: esyPrefixPath};
    }
    return promiseExec(`${ESYCOMMAND} ${args}`, {
      cwd: projectPath,
      env,
    })
  }

  return {rootPath, binPath, projectPath, esy}
}

module.exports = {
  initFixture,
  promiseExec,
};
