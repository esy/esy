// @flow

const {createSandbox} = require('./setup.js');
const fs = require('fs');
const os = require('os');
const path = require('path');

console.log('Check if macos exits with 127 due to sandbox-exec issues [MacOS only]');
const sandbox = createSandbox();
console.log(`*** sandboxPath: ${sandbox.path}`);

const packageJson = {
  esy: {
    build: 'true',
  },
  dependencies: {
    '@opam/alcotest': '0.8.5',
    '@opam/async': 'v0.11.0',
    '@opam/async_ssl': 'v0.11.0',
    '@opam/core': 'v0.11.3',
    '@opam/dune': '*',
    '@opam/httpaf': '0.6.0',
    '@opam/httpaf-async': '0.6.0',
    '@opam/yojson': '1.7.0',
    ocaml: '~4.7.1004',
    pesy: '0.4.3',
  },
  devDependencies: {
    '@opam/merlin': '*',
    '@opam/ocamlformat': '*',
    '@opam/utop': '*',
  },
  resolutions: {
    pesy: 'esy/pesy#ba6359f25621280a8105d2ffc99d75d849c0d95a',
  },
};

fs.writeFileSync(
  path.join(sandbox.path, 'package.json'),
  JSON.stringify(packageJson, null, 2),
);

sandbox.esy('install');
sandbox.esy('build');

sandbox.dispose();
