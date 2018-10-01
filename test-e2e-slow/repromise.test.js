// @flow

const {setup, createSandbox} = require('./setup.js');

setup();

const sandbox = createSandbox();

console.log(`*** Repromise workflow test at ${sandbox.path} ***`);

sandbox.exec('git', 'clone', 'https://github.com/aantron/repromise');
sandbox.cd('./repromise');
sandbox.esy('install');
sandbox.esy('build');
sandbox.esy('build', 'dune', 'build', 'test/test_main.exe');
sandbox.esy('dune', 'exec', 'test/test_main.exe');
sandbox.dispose();
