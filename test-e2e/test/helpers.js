// @flow

jest.setTimeout(20000);

const path = require('path');
const fs = require('fs-extra');
const os = require('os');
const childProcess = require('child_process');
const {promisify} = require('util');
const promiseExec = promisify(childProcess.exec);
const {ocamlPackagePath} = require('./jestGlobalSetup.js');

const isWindows = process.platform === "win32"

const ESYCOMMAND = isWindows 
    ? require.resolve('../../_release/_build/default/esy/bin/esyCommand.exe') 
    : require.resolve('../../bin/esy');

function getTempDir() {
    return isWindows ? os.tmpdir() : '/tmp';
}

const exeExtension = isWindows ? ".exe" : "";

type Fixture = Array<FixtureItem>;
type FixtureItem = FixtureDir | FixtureFile | FixtureFileCopy | FixtureSymlink;
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
type FixtureFileCopy = {
  type: 'file-copy',
  name: string,
  path: string,
};
type FixtureSymlink = {
  type: 'symlink',
  name: string,
  path: string,
};

function dir(name: string, ...items: Array<FixtureItem>): FixtureDir {
  return {type: 'dir', name, items};
}

function file(name: string, data: string): FixtureFile {
  return {type: 'file', name, data};
}

function symlink(name: string, path: string): FixtureSymlink {
  return {type: 'symlink', name, path};
}

function packageJson(json: Object) {
  return file('package.json', JSON.stringify(json, null, 2));
}

let ocamlPackageCached = null;

function ocamloptName() {
    return isWindows ? 'ocamlopt.exe' : 'ocamlopt';
}

function ocamlPackage() {
  if (ocamlPackageCached == null) {
    let packageJson: FixtureFileCopy = {
      type: 'file-copy',
      name: 'package.json',
      path: path.join(ocamlPackagePath, 'package.json'),
    };
    let ocamlopt: FixtureFileCopy = {
      type: 'file-copy',
      name: ocamloptName(),
      path: path.join(ocamlPackagePath, ocamloptName()),
    };
    ocamlPackageCached = dir('ocaml', ocamlopt, packageJson);
    return ocamlPackageCached;
  } else {
    return ocamlPackageCached;
  }
}

async function genFixture(...fixture: Fixture) {
  // use /tmp on unix b/c sometimes it's too long to host the esy store
  const tmp = isWindows ? os.tmpdir() : '/tmp';
  const rootPath = await fs.mkdtemp(path.join(tmp, 'XXXX'));
  const projectPath = path.join(rootPath, 'project');
  const binPath = path.join(rootPath, 'bin');
  const npmPrefixPath = path.join(rootPath, 'npm');
  const esyPrefixPath = path.join(rootPath, 'esy');

  await fs.mkdir(binPath);
  await fs.mkdir(projectPath);
  await fs.mkdir(npmPrefixPath);
  await fs.symlink(ESYCOMMAND, path.join(binPath, 'esy'));

  async function layout(p: string, fixture: FixtureItem) {
    if (fixture.type === 'file') {
      await fs.writeFile(path.join(p, fixture.name), fixture.data);
    } else if (fixture.type === 'file-copy') {
      await fs.copyFile(fixture.path, path.join(p, fixture.name));
    } else if (fixture.type === 'symlink') {
      await fs.symlink(fixture.path, path.join(p, fixture.name));
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

  function npm(args: string) {
    return promiseExec(`npm --prefix ${npmPrefixPath} ${args}`, {
      // this is only used in the release test for now
      cwd: path.join(projectPath, '_release'),
    });
  }

  return {rootPath, binPath, projectPath, esy, npm, esyPrefixPath, npmPrefixPath};
}

function skipSuiteOnWindows(blockingIssues) {
   if (process.platform === 'win32') {
      fdescribe("", () => {
         fit('does not work on Windows', () => {
            console.warn('[SKIP] Needs to be unblocked: ' + blockingIssues);
         });
      });
   }
}

module.exports = {
  promiseExec,
  file,
  symlink,
  dir,
  packageJson,
  genFixture,
  getTempDir,
  skipSuiteOnWindows,
  ESYCOMMAND,
  exeExtension,
  ocamloptName,
  ocamlPackage,
  ocamlPackagePath,
};
