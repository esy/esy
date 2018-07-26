require('babel-register', {
  presets: ['flow', 'env'],
  plugins: ['transform-es2015-destructuring', 'transform-object-rest-spread'],
});

const fs = require('fs-extra');

const {genFixture, packageJson} = require('./helpers');

module.exports = async function jestGlobalSetup(_globalConfig) {
  global.__TEST_PATH__ = '/tmp/esy-test';

  try {
    await fs.mkdir(global.__TEST_PATH__);
  } catch (e) {
    // doesn't matter if it exists
  }

  const p = await genFixture(
    packageJson({
      name: 'root-project',
      version: '1.0.0',
      dependencies: {
        ocaml: '~4.6.1',
      },
      esy: {
        build: [],
        install: [],
      },
    }),
  );

  await p.esy('install');
  await p.esy('build');
};
