// @flow

const {createSandbox, createSandboxFromGitRepo} = require('./setup.js');
const fs = require('fs');
const os = require('os');
const path = require('path');

const cases = [
  'https://github.com/esy/melange-esy-template.git'
];

for (let c of cases) {
  console.log(`*** testing ${c}`);
  const sandbox = createSandboxFromGitRepo(c);

  sandbox.esy('install');
  sandbox.esy('build');
  sandbox.esy('run-script', 'bundle');
  sandbox.dispose();
}
