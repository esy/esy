const fs = require('fs-extra');
const os = require('os');
const path = require('path');
const childProcess = require('child_process');
const {promisify} = require('util');
const promiseExec = promisify(childProcess.exec);

const ESYCOMMAND = require.resolve('../../bin/esy');

module.exports = async function jestGlobalSetup(_globalConfig) {
  global.__TEST_PATH__ = path.join(os.homedir(), '.esytest');

  try {
    await fs.mkdir(global.__TEST_PATH__);
  } catch (e) {
    // doesn't matter if it exists
  }

  const p = await genFixture(
    JSON.stringify({
      name: 'root-project',
      version: '1.0.0',
      dependencies: {
        ocaml: '~4.6.1',
      },
      esy: {
        build: [],
        install: [],
      },
    }),
  );

  await p.esy('install');
  await p.esy('build');
};

async function genFixture(...fixture) {
  const rootPath = await fs.mkdtemp(path.join(global.__TEST_PATH__, 'XXXX'));
  const projectPath = path.join(rootPath, 'project');
  const binPath = path.join(rootPath, 'bin');
  const esyPrefixPath = path.join(global.__TEST_PATH__, 'esy');

  await fs.mkdir(binPath);
  await fs.mkdir(projectPath);
  await fs.link(ESYCOMMAND, path.join(binPath, 'esy'));

  await fs.writeFile(path.join(projectPath, 'package.json'), fixture);

  function esy(args, options) {
    options = options || {};

    return promiseExec(`${ESYCOMMAND} ${args}`, {
      cwd: projectPath,
      env: {...process.env, ESY__PREFIX: esyPrefixPath},
    });
  }

  return {rootPath, binPath, projectPath, esy};
}
