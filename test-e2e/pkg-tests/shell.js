// @flow

const {
  tests: {startPackageServer},
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
  const env = {
    ...process.env,
    PATH: `${esyBin}:${process.env.PATH || ''}`,
    NPM_CONFIG_REGISTRY: registryUrl,
    ESYI__OPAM_REPOSITORY: ':' + path.join(currentDir, 'opam-repository'),
    ESYI__OPAM_OVERRIDE: ':' + path.join(currentDir, 'esy-opam-override'),
  };
  const cwd = await createTemporaryFolder();

  const dependencies = {};
  for (let i = 2; i < process.argv.length; i++) {
    const [_, name, version] = /(@?[^@]+)@?(.*)/.exec(process.argv[i]);
    dependencies[name] = version;
  }

  const packageJson = {
    name: 'root',
    version: '0.0.0',
    dependencies,
  };
  await fs.writeFile(
    path.join(cwd, 'package.json'),
    JSON.stringify(packageJson, null, 2) + '\n',
  );

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
