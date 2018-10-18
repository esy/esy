// @flow

jest.setTimeout(120000);

import type {Fixture} from './FixtureUtils.js';
import type {PackageRegistry} from './NpmRegistryMock.js';
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
const outdent = require('outdent');

const isWindows = process.platform === 'win32';

const ESY = require.resolve('../../_build/default/esy/bin/esyCommand.exe');

function dummyExecutable(name: string) {
  return FixtureUtils.file(
    `${name}.js`,
    outdent`
      console.log("__" + ${JSON.stringify(name)} + "__");
    `,
  );
}

export type TestSandbox = {
  rootPath: string,
  binPath: string,
  projectPath: string,
  esyPrefixPath: string,
  npmPrefixPath: string,
  npmRegistry: PackageRegistry,

  fixture: (...fixture: Fixture) => Promise<void>,

  run: (args: string) => Promise<{stderr: string, stdout: string}>,
  esy: (
    args?: string,
    options: ?{noEsyPrefix?: boolean, env?: Object, p?: string},
  ) => Promise<{stderr: string, stdout: string}>,
  printEsy: (
    args?: string,
    options: ?{noEsyPrefix?: boolean, env?: Object, p?: string},
  ) => Promise<void>,
  npm: (args: string) => Promise<{stderr: string, stdout: string}>,

  runJavaScriptInNodeAndReturnJson: string => Promise<Object>,

  defineNpmPackage: (
    packageJson: {name: string, version: string},
    options?: {distTag?: string, shasum?: string},
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
    },
    fixture: Fixture,
  ) => Promise<void>,
};

function exe(name) {
  return isWindows ? `${name}.exe` : name;
}

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
  await fs.symlink(ESY, path.join(binPath, exe('esy')));
  await fs.copyFile(process.execPath, path.join(binPath, exe('node')));

  await FixtureUtils.initialize(projectPath, fixture);
  const npmRegistry = await NpmRegistryMock.initialize();
  const opamRegistry = await OpamRegistryMock.initialize();

  async function runJavaScriptInNodeAndReturnJson(script) {
    const pnpJs = path.join(projectPath, '_esy', 'default', 'pnp.js');
    const command = `node -r ${pnpJs} -p "JSON.stringify(${script.replace(
      /"/g,
      '\\"',
    )})"`;
    const p = await promiseExec(command, {cwd: projectPath});
    return JSON.parse(p.stdout);
  }

  function esy(args, options) {
    options = options || {};
    let env = {
      ...process.env,
      PATH: `${binPath}${path.delimiter}${process.env.PATH || ''}`,
    };
    if (options.env != null) {
      env = {...env, ...options.env};
    }
    let cwd = projectPath;
    if (options.cwd != null) {
      cwd = options.cwd;
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

    const execCommand = args != null ? `${ESY} ${args}` : ESY;
    return promiseExec(execCommand, {cwd, env});
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

  async function printEsy(cmd, options) {
    const {stdout, stderr} = await esy(cmd, options);
    console.log(
      outdent`
      COMMAND: esy ${cmd}
      STDOUT:

      ${stdout}
      STDERR:

      ${stderr}
      `,
    );
  }

  return {
    rootPath,
    binPath,
    projectPath,
    esyPrefixPath,
    npmPrefixPath,
    run,
    esy,
    printEsy,
    npm,
    npmRegistry,
    fixture: async (...fixture) => {
      await FixtureUtils.initialize(projectPath, fixture);
    },
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

function buildCommand(p: TestSandbox, input: string) {
  let node;
  if (isWindows) {
    node = path.join(p.binPath, 'node.exe');
  } else {
    node = process.execPath;
  }
  return [node, require.resolve('./buildCmd.js'), input];
}

function buildCommandInOpam(input: string) {
  const genWrapper = JSON.stringify(require.resolve('./buildCmd.js'));
  const node = JSON.stringify(process.execPath);
  return `[${node} ${genWrapper} ${JSON.stringify(input)}]`;
}

module.exports = {
  promiseExec,
  file: FixtureUtils.file,
  symlink: FixtureUtils.symlink,
  dir: FixtureUtils.dir,
  packageJson: FixtureUtils.packageJson,
  json: FixtureUtils.json,
  skipSuiteOnWindows,
  getPackageArchiveHash: NpmRegistryMock.getPackageArchiveHash,
  getPackageDirectoryPath: NpmRegistryMock.getPackageDirectoryPath,
  getPackageHttpArchivePath: NpmRegistryMock.getPackageHttpArchivePath,
  getPackageArchivePath: NpmRegistryMock.getPackageArchivePath,
  crawlLayout: PackageGraph.crawl,
  readInstalledPackages: PackageGraph.read,
  makeFakeBinary: fsUtils.makeFakeBinary,
  exists: fs.exists,
  readdir: fs.readdir,
  readFile: fs.readFile,
  execFile: exec.execFile,
  createTestSandbox,
  isWindows,
  dummyExecutable,
  buildCommand,
  buildCommandInOpam,
};
