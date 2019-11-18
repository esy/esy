// @flow

const {createSandbox} = require('./setup.js');
const fs = require('fs');
const os = require('os');
const path = require('path');

const cases = [
  {
    name: 'react',
    test: `
      require('react');
    `,
  },
  // {
  //   name: 'bs-platform',
  // },
  // {
  //   name: 'webpack',
  //   test: `
  //     require('webpack');
  //   `,
  // },
  // {
  //   name: 'jest-cli',
  //   test: `
  //     require('jest-cli');
  //   `,
  // },
  {
    name: 'flow-bin',
    test: `
      require('flow-bin');
    `,
  },
  // {
  //   name: 'babel-cli',
  // },
  // {
  //   name: 'react-scripts',
  //   test: `
  //     require('react-scripts/bin/react-scripts.js');
  //   `,
  // },
];

// All of these tests are blocked by issue #506 on Windows
// TODO: Fix #506 and enable these!
const windowsBlacklist = ['webpack', 'jest-cli', 'babel-cli', 'react-scripts'];

let p;
let reposUpdated = false;

for (let c of cases) {
  if (os.platform() === 'win32' && windowsBlacklist.indexOf(c.name) >= 0) {
    console.warn(`Skipping ${c.name} on Windows due to blocking bug.`);
    continue;
  }

  console.log(`*** installing ${c.name}`);
  const sandbox = createSandbox();
  console.log(`*** sandboxPath: ${sandbox.path}`);

  const packageJson = {
    name: `test-${c.name}`,
    version: '0.0.0',
    esy: {build: ['true']},
    dependencies: {
      [c.name]: '*',
    },
  };

  fs.writeFileSync(
    path.join(sandbox.path, 'package.json'),
    JSON.stringify(packageJson, null, 2),
  );

  sandbox.esy('install');
  sandbox.esy('build');

  if (c.test != null) {
    const test = c.test;
    fs.writeFileSync(path.join(sandbox.path, 'test.js'), test);
    sandbox.esy('node', './test.js');
  }

  sandbox.dispose();
}
