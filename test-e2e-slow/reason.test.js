// @flow

const {setup, createSandbox} = require('./setup.js');

setup();

const sandbox = createSandbox();

console.log(`*** Reason workflow test at ${sandbox.path} ***`);

sandbox.exec('git', 'clone', 'https://github.com/facebook/reason');
sandbox.cd('./reason');
sandbox.esy('install');
sandbox.esy('build');
sandbox.esy('x', 'which', 'refmt');
sandbox.esy('x', 'refmt', '--version');
sandbox.dispose();
