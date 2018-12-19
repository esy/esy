// @flow

const path = require('path');
const fs = require('fs');
const {setup, createSandbox} = require('./setup.js');

setup();

const sandbox = createSandbox();

console.log(`*** C workflow test at ${sandbox.path} ***`);

const fixture = path.join(__dirname, 'c-workflow');
sandbox.exec(`cp -rf ${fixture} ./project`);
sandbox.cd('./project');

sandbox.esy('install');
sandbox.esy('build');
sandbox.esy('x', 'which', 'main');
sandbox.esy('x', 'main');
sandbox.dispose();

