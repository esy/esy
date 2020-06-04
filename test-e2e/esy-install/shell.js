// @noflow

const {
  tests: {startPackageServer, definePackage},
  fs: {createTemporaryFolder},
} = require(`pkg-tests-core`);
const fs = require('fs-extra');
const path = require('path');
const cp = require('child_process');

const currentDir = __dirname;

const esyBin = path.join(currentDir, '..', '..', '_build', 'install', 'default', 'bin');

function spawnShell({env, cwd}) {
  return new Promise((resolve, reject) => {
    const p = cp.spawn('/bin/bash', ['-i'], {env, cwd, stdio: 'inherit'});
    p.on('exit', code => {
      if (code === 0) {
        resolve();
      } else {
        // We ignore failure from interactive sesssion.
        resolve();
      }
    });
  });
}

async function main() {
  const registryUrl = await startPackageServer();
  const cwd = await createTemporaryFolder();
  const env = Object.assign({}, process.env, {
    PATH: `${esyBin}:${process.env.PATH || ''}`,
    NPM_CONFIG_REGISTRY: registryUrl,
    ESYI__CACHE: path.join(cwd, 'cache'),
    ESYI__OPAM_REPOSITORY_LOCAL: path.join(currentDir, 'opam-repository'),
    ESYI__OPAM_OVERRIDE_LOCAL: path.join(currentDir, 'esy-opam-override'),
  });

  await definePackage({
    name: 'dep',
    version: '1.0.0',
    dependencies: {depDep: `1.0.0`},
  });
  await definePackage({
    name: 'depDep',
    version: '1.0.0',
  });
  await definePackage({
    name: 'depDep',
    version: '2.0.0',
  });

  const packageJson = {
    name: 'root',
    version: '1.0.0',
    dependencies: {dep: `1.0.0`},
    resolutions: {depDep: `2.0.0`},
  };
  await fs.writeFile(path.join(cwd, 'package.json'), JSON.stringify(packageJson, null, 2) + '\n');

  try {
    await spawnShell({env, cwd, stdio: 'inherit'});
  } finally {
    await fs.remove(cwd);
  }
}

process.on('unhandledRejection', error => {
  console.log('unhandledRejection', error.message);
  process.exit(1);
});

main();
