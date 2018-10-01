// @flow

const {setup, createSandbox} = require('./setup.js');

setup();

const sandbox = createSandbox();

console.log(`*** Esy workflow test at ${sandbox.path} ***`);

sandbox.exec('git', 'clone', 'https://github.com/esy/esy');
sandbox.cd('./esy');
sandbox.esy('install');
sandbox.esy('build');
sandbox.esy('x', 'which', 'esy');
sandbox.esy('x', 'esy', '--version');
sandbox.dispose();
