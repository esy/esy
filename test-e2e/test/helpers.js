// @flow

jest.setTimeout(120000);

import type {Fixture} from './FixtureUtils.js';
import type {PackageRegistry} from './NpmRegistryMock.js';
import type {OpamRegistry} from './OpamRegistryMock.js.js';
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
const pkgJson = require('../../package.json');

const isWindows = process.platform === 'win32';
const isLinux = process.platform === 'linux';
const isMacos = process.platform === 'darwin';

// This is set in jest.config.js
declare var __ESY__: string;

const ESY = __ESY__;

const getWindowsSystemDirectory = () => {
  return path
    .join(process.env['windir'], 'System32')
    .split('\\')
    .join('/');
};

var regexpRe = /[|\\{}()[\]^$+*?.]/g;

function escapeForRegexp(str) {
  return str.replace(regexpRe, '\\$&');
}

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
  esyStorePath: string,
  npmPrefixPath: string,
  npmRegistry: PackageRegistry,
  opamRegistry: OpamRegistry,

  fixture: (...fixture: Fixture) => Promise<void>,

  run: (args: string, env?: Object) => Promise<{stderr: string, stdout: string}>,

  cd: (where: string) => void,

  esy: (
    args?: string,
    options: ?{noEsyPrefix?: boolean, env?: Object, p?: string},
  ) => Promise<{stderr: string, stdout: string}>,
  printEsy: (
    args?: string,
    options: ?{noEsyPrefix?: boolean, env?: Object, p?: string},
  ) => Promise<void>,
  npm: (args: string) => Promise<{stderr: string, stdout: string}>,

  normalizePathsForSnapshot: (string, replacements?: {[s: string]: string}) => string,
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

var STORE_BUILD_TREE = 'b';
var STORE_INSTALL_TREE = 'i';
var STORE_STAGE_TREE = 's';
var ESY_STORE_VERSION = 3;
var MAX_SHEBANG_LENGTH = 127;
var OCAMLRUN_STORE_PATH = 'ocaml-n.00.0000-########/bin/ocamlrun';
var ESY_STORE_PADDING_LENGTH =
  MAX_SHEBANG_LENGTH -
  '!#'.length -
  ('/' + STORE_INSTALL_TREE + '/' + OCAMLRUN_STORE_PATH).length;

function getStorePathForPrefix(prefix) {
  if (isWindows && process.env['ESY__WINDOWS_SHORT_PATHS']) {
    return path.join(prefix, '3_');
  } else {
    var prefixLength = path.join(prefix, String(ESY_STORE_VERSION)).length;
    var paddingLength = ESY_STORE_PADDING_LENGTH - prefixLength;
    if (paddingLength < 0) {
      throw new Error(
        "Esy prefix path is too deep in the filesystem, Esy won't be able to relocate artefacts",
      );
    }
    var p = path.join(prefix, String(ESY_STORE_VERSION));
    while (p.length < ESY_STORE_PADDING_LENGTH) {
      p = p + '_';
    }
    return p;
  }
}

const CREATED_SANDBOXES = [];

async function createTestSandbox(...fixture: Fixture): Promise<TestSandbox> {
  // use /tmp on unix b/c sometimes it's too long to host the esy store
  const tmp = isWindows ? os.tmpdir() : '/tmp';
  const rootPath = await fs.realpath(await fs.mkdtemp(path.join(tmp, 'XXXX')));
  CREATED_SANDBOXES.push(rootPath);
  const projectPath = path.join(rootPath, 'project');
  const binPath = path.join(rootPath, 'bin');
  const npmPrefixPath = path.join(rootPath, 'npm');
  const esyPrefixPath = path.join(rootPath, 'esy');

  await fs.mkdir(binPath);
  await fs.mkdir(projectPath);
  await fs.mkdir(npmPrefixPath);
  await fs.symlink(ESY, path.join(binPath, exe('esy')));
  await fs.symlink(process.execPath, path.join(binPath, exe('node')));

  await FixtureUtils.initialize(projectPath, fixture);
  const npmRegistry = await NpmRegistryMock.initialize();
  const opamRegistry = await OpamRegistryMock.initialize();

  const envForTests = {
    ESY__PREFIX: esyPrefixPath,
    ESYI__OPAM_REPOSITORY_LOCAL: opamRegistry.registryPath,
    ESYI__OPAM_OVERRIDE_LOCAL: opamRegistry.overridePath,
    NPM_CONFIG_REGISTRY: npmRegistry.serverUrl,
  };

  // put this into project root for debug
  const envSource = [];
  for (const key in envForTests) {
    const value = envForTests[key];
    envSource.push(`export ${key}='${value}'`);
  }
  await fs.writeFile(path.join(projectPath, 'test-env'), envSource.join('\n') + '\n');

  async function runJavaScriptInNodeAndReturnJson(script) {
    const pnpJs = path.join(projectPath, '_esy', 'default', 'pnp.js');
    const command = `node -r ${pnpJs} -p "JSON.stringify(${script.replace(
      /"/g,
      '\\"',
    )})"`;
    const p = await promiseExec(command, {cwd});
    return JSON.parse(p.stdout);
  }

  async function esy(args, options) {
    const p = Promise.resolve().then(() => {
      options = options || {};
      let env = {
        ...process.env,
        PATH: `${binPath}${path.delimiter}${process.env.PATH || ''}`,
      };
      if (options.env != null) {
        env = {...env, ...options.env};
      }
      if (!options.noEsyPrefix) {
        env = {
          ...env,
          ...envForTests,
        };
      }

      const execCommand = args != null ? `${ESY} ${args}` : ESY;
      // this is required so esy won't "attach" to the outer esy project (esy
      // itself)
      delete env.ESY__ROOT_PACKAGE_CONFIG_PATH;
      return promiseExec(execCommand, {cwd, env: {...env, "_": execCommand.split(' ')[0] }});
    });
    return p.catch(err => {
      err.stdout = normalizeEOL(err.stdout);
      err.stderr = normalizeEOL(err.stderr);
      throw err;
    });
  }

  function npm(args: string) {
    return promiseExec(`npm --prefix ${npmPrefixPath} ${args}`, {
      // this is only used in the release test for now
      cwd: path.join(projectPath, '_release'),
    });
  }

  function run(line: string, env) {
    if (env == null) {
      env = process.env;
    }
    // this is required so esy won't "attach" to the outer esy project (esy
    // itself)
    delete env.ESY__ROOT_PACKAGE_CONFIG_PATH;
    return promiseExec(line, {cwd, env});
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

  let cwd = projectPath;

  function cd(where) {
    cwd = path.resolve(cwd, where);
  }

  const esyStorePath = getStorePathForPrefix(esyPrefixPath);

  const projectPathRe = new RegExp(escapeForRegexp(projectPath), 'g');
  const esyPrefixPathRe = new RegExp(escapeForRegexp(esyPrefixPath), 'g');
  const esyStorePathRe = new RegExp(escapeForRegexp(esyStorePath), 'g');

  function normalizePathsForSnapshot(data, replacements) {
    data = data
      .replace(projectPathRe, '%projectPath%')
      .replace(esyStorePathRe, '%esyStorePath%')
      .replace(esyPrefixPathRe, '%esyPrefixPath%');
    for (let to in replacements) {
      data = data.replace(
        new RegExp(escapeForRegexp(replacements[to]), 'g'),
        '%' + to + '%',
      );
    }
    return data;
  }

  return {
    cd,
    rootPath,
    binPath,
    projectPath: projectPath.replace(/\\/g, '/'),
    esyPrefixPath: esyPrefixPath.replace(/\\/g, '/'),
    esyStorePath: esyStorePath.replace(/\\/g, '/'),
    npmPrefixPath: npmPrefixPath.replace(/\\/g, '/'),
    run,
    esy,
    printEsy,
    npm,
    npmRegistry,
    opamRegistry,
    normalizePathsForSnapshot,
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

afterAll(function() {
  if (process.env.TEST_ESY_DEBUG != undefined) {
    for (const p of CREATED_SANDBOXES) {
      fs.removeSync(p);
    }
  }
});

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

function normalizeEOL(string: string) {
  return string.replace(/(\r\n)|\r/g, '\n');
}

function createDefineTest(params) {
  function deftest(name: string, fn: (done: () => void) => ?Promise<mixed>) {
    if (params.disabled) {
      return test.skip(name, fn);
    } else if (params.focused) {
      return test.only(name, fn);
    } else {
      return test(name, fn);
    }
  }
  // $FlowFixMe
  Object.defineProperty(deftest, 'only', {
    get() {
      return createDefineTest({...params, focused: true});
    },
  });
  // $FlowFixMe
  Object.defineProperty(deftest, 'skip', {
    get() {
      return createDefineTest({...params, disabled: true});
    },
  });
  // $FlowFixMe
  Object.defineProperty(deftest, 'disable', {
    get() {
      return createDefineTest({...params, disabled: true});
    },
  });
  deftest.disableIf = function(cond) {
    if (cond) {
      return createDefineTest({...params, disabled: true});
    } else {
      return createDefineTest({...params, disabled: false});
    }
  };
  deftest.enableIf = function(cond) {
    if (cond) {
      return createDefineTest({...params, disabled: false});
    } else {
      return createDefineTest({...params, disabled: true});
    }
  };
  return deftest;
}

module.exports = {
  test: createDefineTest({disabled: false, focused: false}),
  normalizeEOL,
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
  getWindowsSystemDirectory,
  dummyExecutable,
  buildCommand,
  buildCommandInOpam,
  esyVersion: pkgJson.version,

  ESY,
  isWindows,
  isLinux,
  isMacos,
};
