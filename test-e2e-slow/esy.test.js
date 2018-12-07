// @flow

const {setup, createSandbox} = require('./setup.js');

setup();

const sandbox = createSandbox();

console.log(`*** Esy workflow test at ${sandbox.path} ***`);

sandbox.exec('git', 'clone', 'https://github.com/esy/esy');
sandbox.cd('./esy');
sandbox.rm('./esy.lock.json');
sandbox.esy('install');
sandbox.esy('build');
sandbox.esy('x', 'which', 'esy');
sandbox.dispose();
