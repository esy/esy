// @flow

const {setup, createSandbox} = require('./setup.js');

setup();

const sandbox = createSandbox();

console.log(`*** Fastpack workflow test at ${sandbox.path} ***`);

sandbox.exec('git', 'clone', 'https://github.com/fastpack/fastpack');
sandbox.cd('./fastpack');
sandbox.exec('git', 'submodule', 'init');
sandbox.exec('git', 'submodule', 'update');
sandbox.esy('install');
sandbox.exec('bash', '-c', 'node scripts/gen_link_flags.js > bin/link_flags');
sandbox.esy('build');
sandbox.esy('x', 'fpack', '--version');
sandbox.dispose();
