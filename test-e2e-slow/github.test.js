// @flow

const {createSandbox, createSandboxFromGitRepo} = require('./setup.js');
const fs = require('fs');
const os = require('os');
const path = require('path');

const cases = [
  'https://github.com/esy/test-github-long-hash',
  'https://github.com/esy/test-github-short-hash',
];

for (let c of cases) {
  console.log(`*** testing ${c}`);
  const sandbox = createSandboxFromGitRepo(c);

  sandbox.esy('install');
  sandbox.esy('build');
  sandbox.esy('x', 'hello.exe');
  sandbox.dispose();
}
