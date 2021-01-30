// @flow

const {execSync} = require('child_process');
const fs = require('fs');
const path = require('path');
const esyJson = require('../esy.json');
const packageJson = require('../package.json');

function exec(cmd) {
  console.log(`exec: ${cmd}`);
  return execSync(cmd).toString();
}

function mkdirpSync(p) {
  if (fs.existsSync(p)) {
    return;
  }
  mkdirpSync(path.dirname(p));
  fs.mkdirSync(p);
}

function removeSync(p) {
  exec(`rm -rf "${p}"`);
}

const args = process.argv.slice(2);
const commit = args[0] != null ? args[0] : exec(`git rev-parse --verify HEAD`);

const src = path.resolve(path.join(__dirname, '..'));
const dst = path.resolve(path.join(__dirname, '..', '_release'));

removeSync(dst);
mkdirpSync(dst);

const filesToCopy = ['LICENSE', 'README.md'];

for (const file of filesToCopy) {
  const p = path.join(dst, file);
  mkdirpSync(path.dirname(p));
  fs.copyFileSync(path.join(src, file), p);
}

fs.copyFileSync(
  path.join(src, 'scripts', 'release-postinstall.js'),
  path.join(dst, 'postinstall.js')
);

const filesToTouch = [
  '_build/default/bin/esy.exe',
  '_build/default/lib/esy/esyBuildPackageCommand.exe',
  '_build/default/bin/fastreplacestring.exe'
];

for (const file of filesToTouch) {
  const p = path.join(dst, file);
  mkdirpSync(path.dirname(p));
  fs.writeFileSync(p, '');
}

const pkgJson = {
  name: '@esy-nightly/esy',
  version: `${esyJson.version}-${commit.slice(0, 6)}`,
  license: esyJson.license,
  description: esyJson.description,
  repository: esyJson.repository,
  dependencies: {
    'esy-solve-cudf': packageJson.devDependencies['esy-solve-cudf']
  },
  scripts: {
    postinstall: 'node ./postinstall.js'
  },
  bin: {
    esy: '_build/default/bin/esy.exe'
  },
  files: [
    'bin/',
    'postinstall.js',
    'Linux/',
    'macOS/',
    'Windows/',
    '_build/default/**/*.exe'
  ]
};

fs.writeFileSync(path.join(dst, 'package.json'), JSON.stringify(pkgJson, null, 2));
