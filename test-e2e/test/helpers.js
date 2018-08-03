// @flow

jest.setTimeout(120000);

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
const PackageGraph = require('./PackageGraph.js');
const NpmRegistryMock = require('./NpmRegistryMock.js');
const OpamRegistryMock = require('./OpamRegistryMock.js');
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

function ocamlPackage() {
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
  return FixtureUtils.dir('ocaml', ocamlopt, packageJson);
}

export type TestSandbox = {
  rootPath: string,
  binPath: string,
  projectPath: string,
  esyPrefixPath: string,
  npmPrefixPath: string,

  run: (args: string) => Promise<{stderr: string, stdout: string}>,
  esy: (
    args?: string,
    options: ?{noEsyPrefix?: boolean, env?: Object},
  ) => Promise<{stderr: string, stdout: string}>,
  npm: (args: string) => Promise<{stderr: string, stdout: string}>,

  runJavaScriptInNodeAndReturnJson: string => Promise<Object>,

  defineNpmPackage: (
    packageJson: {name: string, version: string},
    options?: {shasum?: string},
  ) => Promise<string>,

  defineNpmPackageOfFixture: (fixture: Fixture) => Promise<void>,

  defineNpmLocalPackage: (
    packagePath: string,
    packageJson: {name: string, version: string},
  ) => Promise<void>,

  defineOpamPackage: (spec: {
    name: string,
    version: string,
    opam: string,
    url: ?string,
  }) => Promise<void>,
  defineOpamPackageOfFixture: (
    spec: {
      name: string,
      version: string,
      opam: string,
      url: ?string,
    },
    fixture: Fixture,
  ) => Promise<void>,
};

async function createTestSandbox(...fixture: Fixture): Promise<TestSandbox> {
  // use /tmp on unix b/c sometimes it's too long to host the esy store
  const tmp = isWindows ? os.tmpdir() : '/tmp';
  const rootPath = await fs.realpath(await fs.mkdtemp(path.join(tmp, 'XXXX')));
  const projectPath = path.join(rootPath, 'project');
  const binPath = path.join(rootPath, 'bin');
  const npmPrefixPath = path.join(rootPath, 'npm');
  const esyPrefixPath = path.join(rootPath, 'esy');

  await fs.mkdir(binPath);
  await fs.mkdir(projectPath);
  await fs.mkdir(npmPrefixPath);
  await fs.symlink(ESYCOMMAND, path.join(binPath, 'esy'));

  await FixtureUtils.initialize(projectPath, fixture);
  const npmRegistry = await NpmRegistryMock.initialize();
  const opamRegistry = await OpamRegistryMock.initialize();

  async function runJavaScriptInNodeAndReturnJson(script) {
    const command = `node -p "JSON.stringify(${script.replace(/"/g, '\\"')})"`;
    const p = await promiseExec(command, {cwd: projectPath});
    return JSON.parse(p.stdout);
  }

  function esy(args, options) {
    options = options || {};
    let env = process.env;
    if (options.env != null) {
      env = {...env, ...options.env};
    }
    if (!options.noEsyPrefix) {
      env = {
        ...env,
        ESY__PREFIX: esyPrefixPath,
        ESYI__CACHE: path.join(esyPrefixPath, 'esyi'),
        ESYI__OPAM_REPOSITORY: `:${opamRegistry.registryPath}`,
        ESYI__OPAM_OVERRIDE: `:${opamRegistry.overridePath}`,
        NPM_CONFIG_REGISTRY: npmRegistry.serverUrl,
      };
    }

    const execCommand = args != null ? `${ESYCOMMAND} ${args}` : ESYCOMMAND;
    return promiseExec(execCommand, {
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

  function run(line: string) {
    return promiseExec(line, {cwd: path.join(projectPath)});
  }

  return {
    rootPath,
    binPath,
    projectPath,
    esyPrefixPath,
    npmPrefixPath,
    run,
    esy,
    npm,
    runJavaScriptInNodeAndReturnJson,
    defineNpmPackage: (pkg, options) =>
      NpmRegistryMock.definePackage(npmRegistry, pkg, options),
    defineNpmPackageOfFixture: (fixture: Fixture) =>
      NpmRegistryMock.definePackageOfFixture(npmRegistry, fixture),
    defineNpmLocalPackage: (path, pkg) =>
      NpmRegistryMock.defineLocalPackage(npmRegistry, path, pkg),
    defineOpamPackage: spec => OpamRegistryMock.defineOpamPackage(opamRegistry, spec),
    defineOpamPackageOfFixture: (spec, fixture: Fixture) =>
      OpamRegistryMock.defineOpamPackageOfFixture(opamRegistry, spec, fixture),
  };
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

module.exports = {
  promiseExec,
  file: FixtureUtils.file,
  symlink: FixtureUtils.symlink,
  dir: FixtureUtils.dir,
  packageJson: FixtureUtils.packageJson,
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
  crawlLayout: PackageGraph.crawl,
  makeFakeBinary: fsUtils.makeFakeBinary,
  exists: fs.exists,
  readdir: fs.readdir,
  execFile: exec.execFile,
  createTestSandbox,
  isWindows,
};
