// @flow

const crypto = require('crypto');
const fs = require('fs-extra');
const os = require('os');
const path = require('path');
const childProcess = require('child_process');
const rmSync = require('rimraf').sync;
const isCi = require('is-ci');

const isWindows = process.platform === 'win32';
const ocamlVersion = '4.14.x';

let __ESY__;
let __ESY__base;
if (process.platform === 'linux') {
  const testEsyPrefix = path.join(__dirname, '.test-esy');
  fs.rmSync(testEsyPrefix, {force: true, recursive: true});
  fs.mkdirSync(testEsyPrefix, {recursive: true});
  fs.cpSync(
    path.resolve(__dirname, '..', '_build', 'install', 'default'),
    testEsyPrefix,
    {
      recursive: true,
      dereference: true,
    },
  );
  __ESY__base = path.join(testEsyPrefix, 'bin');
} else {
  __ESY__base = path.join(process.cwd(), '_build', 'install', 'default', 'bin');
}
__ESY__ = path.join(__ESY__base, 'esy');

if (isWindows) {
  __ESY__ += '.exe';
}
process.env.PATH = __ESY__base + (isWindows ? ';' : ':') + process.env.PATH;

function getTempDir() {
  // The appveyor temp folder has some permission issues -
  // so in that environment, we'll run these tests from a root folder.
  const appVeyorTempFolder = 'C:/esy-ci-temp';
  if (isCi) {
    if (isWindows) {
      return 'C:/esy-ci-temp';
    } else {
      return path.join(process.env['HOME'], 'tmp');
    }
  } else {
    return os.tmpdir();
  }
}

const esyPrefixPath =
  process.env.TEST_ESY_PREFIX != null
    ? process.env.TEST_ESY_PREFIX
    : path.join(getTempDir(), crypto.randomBytes(8).toString('hex'));

function mkdir(path) {
  try {
    fs.mkdirpSync(path);
  } catch (e) {
    // doesn't matter if it exists
  }
}

function mkdirTemp() {
  const p = path.join(getTempDir(), crypto.randomBytes(8).toString('hex'));
  fs.mkdirpSync(p);
  return p;
}

/*::

 type TestSandbox = {
   path: string,
   cd: (where: string) => void,
   rm: (what: string) => void,
   exec: (...args: string[]) => void,
   esy: (...args: string[]) => void,
   dispose: () => void,
 };

*/

// Workaround for some current & intermittent failures on esy:
// - https://github.com/esy/esy/issues/462
// - https://github.com/esy/esy/issues/414
// - https://github.com/esy/esy/issues/413
function retry(fn) {
  if (os.platform() !== 'win32') {
    return fn();
  }

  let iterations = 1;
  let lastException = null;
  while (iterations <= 3) {
    try {
      console.log(' ** Iteration: ' + iterations.toString());
      let ret = fn();
      return ret;
    } catch (ex) {
      console.warn('Exception: ' + ex.toString());
      lastException = ex;
    }

    iterations++;
  }

  throw lastException;
}

function createSandbox() /* : TestSandbox */ {
  const sandboxPath = mkdirTemp();

  let cwd = sandboxPath;

  function exec(...args /* : Array<string> */) {
    const normalizedArgs = args.map((arg) => arg.split('\\').join('/'));
    const cmd = normalizedArgs.join(' ');
    console.log(`EXEC: ${cmd}`);
    childProcess.execSync(cmd, {
      cwd: cwd,
      env: {...process.env, ESY__PREFIX: esyPrefixPath, _: cmd.split(' ')[0]},
      stdio: 'inherit',
    });
  }

  function cd(where) {
    cwd = path.resolve(cwd, where);
    console.log(`CWD: ${cwd}`);
  }

  function rm(what) {
    const p = path.resolve(cwd, what);
    console.log(`RM: ${p}`);
    rmSync(p);
  }

  return {
    path: sandboxPath,
    exec: exec,
    cd,
    rm,
    esy(...args /* : Array<string> */) {
      return retry(() => exec(__ESY__, ...args));
    },
    dispose: () => {
      rmSync(sandboxPath);
    },
  };
}

function createSandboxFromGitRepo(url) {
  let sandbox = createSandbox();
  childProcess.execSync(`git clone ${url} ${sandbox.path}`, {
    cwd: sandbox.path,
    env: {...process.env, ESY__PREFIX: esyPrefixPath},
    stdio: 'inherit',
  });
  return sandbox;
}

function buildOCaml() {
  const sandbox = createSandbox();

  fs.writeFileSync(
    path.join(sandbox.path, 'package.json'),
    JSON.stringify({
      name: 'root-project',
      version: '1.0.0',
      dependencies: {
        ocaml: ocamlVersion,
      },
      esy: {
        build: [],
        install: [],
      },
    }),
  );

  console.log(`*** building OCaml toolchain at ${sandbox.path} ***`);

  sandbox.esy('install');
  sandbox.esy('build');
  sandbox.dispose();
}

function setup(_globalConfig /* : any */) {
  buildOCaml();
}

module.exports.setup = setup;
module.exports.esyPrefixPath = esyPrefixPath;
module.exports.__ESY__ = __ESY__;
module.exports.isWindows = isWindows;
module.exports.mkdirTemp = mkdirTemp;
module.exports.ocamlVersion = ocamlVersion;
module.exports.createSandbox = createSandbox;
module.exports.createSandboxFromGitRepo = createSandboxFromGitRepo;
