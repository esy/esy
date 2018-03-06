/** @flow */

const path = require('path');
const fs = require('fs');

const packageJsonFilename = require.resolve('../esy-install/package.json');
const packageJson = JSON.parse(fs.readFileSync(packageJsonFilename, 'utf8'));

const releasePackageJson = {
  name: packageJson.name,
  version: packageJson.version,
  license: packageJson.license,
  description: packageJson.description,
  dependencies: {
    '@esy-ocaml/esy-opam': packageJson.dependencies['@esy-ocaml/esy-opam'],
    fastreplacestring: packageJson.dependencies['fastreplacestring'],
  },
  scripts: {
    postinstall: 'bash ./scripts/postinstall.sh',
  },
  engines: packageJson.engines,
  repository: packageJson.repository,
  bin: packageJson.bin,
  files: ['bin/', '/scripts'],
};

console.log(JSON.stringify(releasePackageJson, null, 2));
