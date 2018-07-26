// @flow

jest.setTimeout(20000);

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
  const npmPrefixPath = path.join(rootPath, 'npm');

  await fs.mkdir(binPath);
  await fs.mkdir(npmPrefixPath);
  await fs.symlink(ESYCOMMAND, path.join(binPath, 'esy'));
  await fs.copy(fixture, projectPath);

  function npm(args: string) {
    return promiseExec(`npm --prefix ${npmPrefixPath} ${args}`, {
      // this is only used in the release test for now
      cwd: path.join(projectPath, '_release'),
    });
  }

  function esy(args: string, options: ?{noEsyPrefix?: boolean}) {
    options = options || {};
    let env = process.env;
    if (!options.noEsyPrefix) {
      env = {...process.env, ESY__PREFIX: esyPrefixPath};
    }
    env = {...env, PATH: `${binPath}${path.delimiter}${env.PATH || ''}`};
    return promiseExec(`${ESYCOMMAND} ${args}`, {
      cwd: projectPath,
      env,
    });
  }

  return {rootPath, binPath, projectPath, esy, esyPrefixPath, npm, npmPrefixPath};
}

type Fixture = Array<FixtureItem>;
type FixtureItem = FixtureDir | FixtureFile;
type FixtureDir = {
  type: 'dir',
  name: string,
  items: Array<FixtureItem>,
};
type FixtureFile = {
  type: 'file',
  name: string,
  data: string,
};

function dir(name: string, ...items: Array<FixtureItem>): FixtureDir {
  return {type: 'dir', name, items};
}

function file(name: string, data: string): FixtureFile {
  return {type: 'file', name, data};
}

function packageJson(json: Object) {
  return file('package.json', JSON.stringify(json));
}

async function genFixture(...fixture: Fixture) {
  const rootPath = await fs.mkdtemp('/tmp/esy.XXXX');
  const projectPath = path.join(rootPath, 'project');
  const binPath = path.join(rootPath, 'bin');
  const esyPrefixPath = path.join(rootPath, 'esy');

  await fs.mkdir(binPath);
  await fs.mkdir(projectPath);
  await fs.symlink(ESYCOMMAND, path.join(binPath, 'esy'));

  async function layout(p: string, fixture: FixtureItem) {
    if (fixture.type === 'file') {
      await fs.writeFile(path.join(p, fixture.name), fixture.data);
    } else if (fixture.type === 'dir') {
      const nextp = path.join(p, fixture.name);
      await fs.mkdir(nextp);
      await Promise.all(fixture.items.map(item => layout(nextp, item)));
    } else {
      throw new Error('unknown fixture ' + JSON.stringify(fixture));
    }
  }

  await Promise.all(fixture.map(item => layout(projectPath, item)));

  function esy(args: string, options: ?{noEsyPrefix?: boolean}) {
    options = options || {};
    let env = process.env;
    if (!options.noEsyPrefix) {
      env = {...process.env, ESY__PREFIX: esyPrefixPath};
    }
    return promiseExec(`${ESYCOMMAND} ${args}`, {
      cwd: projectPath,
      env,
    });
  }

  return {rootPath, binPath, projectPath, esy, esyPrefixPath};
}

module.exports = {
  initFixture,
  promiseExec,
  file,
  dir,
  packageJson,
  genFixture,
};
