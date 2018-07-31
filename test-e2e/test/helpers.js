// @flow

jest.setTimeout(20000);

import type {Fixture} from './FixtureUtils.js';
const path = require('path');
const fs = require('fs-extra');
const fsUtils = require('./fs.js');
const exec = require('./exec.js');
const os = require('os');
const childProcess = require('child_process');
const {promisify} = require('util');
const promiseExec = promisify(childProcess.exec);
const FixtureUtils = require('./FixtureUtils.js');
const NpmRegistryMock = require('./NpmRegistryMock.js');
const {
  ocamlPackagePath,
  ESYCOMMAND,
  ESYICOMMAND,
  isWindows,
  ocamloptName,
} = require('./jestGlobalSetup.js');

function getTempDir() {
  return isWindows ? os.tmpdir() : '/tmp';
}

const exeExtension = isWindows ? '.exe' : '';

let ocamlPackageCached = null;

function ocamlPackage() {
  if (ocamlPackageCached == null) {
    let packageJson = {
      type: 'file-copy',
      name: 'package.json',
      path: path.join(ocamlPackagePath, 'package.json'),
    };
    let ocamlopt = {
      type: 'file-copy',
      name: ocamloptName,
      path: path.join(ocamlPackagePath, ocamloptName),
    };
    ocamlPackageCached = FixtureUtils.dir('ocaml', ocamlopt, packageJson);
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

  await Promise.all(fixture.map(item => FixtureUtils.initialize(projectPath, item)));

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

function skipSuiteOnWindows(blockingIssues?: string) {
  if (process.platform === 'win32') {
    fdescribe('', () => {
      fit('does not work on Windows', () => {
        console.warn(
          '[SKIP] Needs to be unblocked: ' + (blockingIssues || 'Needs investigation'),
        );
      });
    });
  }
}

const esyiCommands = new Set(['install', 'print-cudf-universe']);

const makeTemporaryEnv = NpmRegistryMock.generatePkgDriver({
  runDriver: (path, line, {registryUrl}) => {
    if (line.length === 1 && esyiCommands.has(line[0])) {
      const extraArgs = [
        `--cache-path`,
        `${path}/.cache`,
        `--npm-registry`,
        registryUrl,
        `--opam-repository`,
        `:${__dirname}/opam-repository`,
        `--opam-override-repository`,
        `:${__dirname}/esy-opam-override`,
      ];
      return exec.execFile(ESYICOMMAND, [...extraArgs], {cwd: path});
    } else {
      const prg = line[0];
      const args = line.slice(1);
      return exec.execFile(prg, [...args], {cwd: path});
    }
  },
});

beforeEach(async function commonBeforeEach() {
  await NpmRegistryMock.clearPackageRegistry();
  await NpmRegistryMock.startPackageServer();
  await NpmRegistryMock.getPackageRegistry();
});

module.exports = {
  promiseExec,
  file: FixtureUtils.file,
  symlink: FixtureUtils.symlink,
  dir: FixtureUtils.dir,
  packageJson: FixtureUtils.packageJson,
  genFixture,
  getTempDir,
  skipSuiteOnWindows,
  ESYCOMMAND,
  exeExtension,
  ocamloptName,
  ocamlPackage,
  ocamlPackagePath,
  getPackageDirectoryPath: NpmRegistryMock.getPackageDirectoryPath,
  getPackageHttpArchivePath: NpmRegistryMock.getPackageHttpArchivePath,
  getPackageArchivePath: NpmRegistryMock.getPackageArchivePath,
  definePackage: NpmRegistryMock.definePackage,
  defineLocalPackage: NpmRegistryMock.defineLocalPackage,
  makeTemporaryEnv: makeTemporaryEnv,
  crawlLayout: NpmRegistryMock.crawlLayout,
  makeFakeBinary: fsUtils.makeFakeBinary,
  exists: fs.exists,
  readdir: fs.readdir,
  execFile: exec.execFile,
};
