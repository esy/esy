// @flow

const outdent = require('outdent');
const helpers = require('../test/helpers');

it('Build - no deps backslash', async () => {
  const p = await helpers.createTestSandbox();

  await p.fixture(
    helpers.packageJson({
      name: 'no-deps-backslash',
      version: '1.0.0',
      license: 'MIT',
      esy: {
        build: [
          ['cp', '#{self.root /}test.js', '#{self.target_dir /}test.js'],
          helpers.buildCommand(p, '#{self.target_dir /}test.js'),
        ],
        install: [
          ['cp', '#{self.target_dir /}test.cmd', '#{self.bin /}test.cmd'],
          ['cp', '#{self.target_dir /}test.js', '#{self.bin /}test.js'],
        ],
      },
    }),
    helpers.file(
      'test.js',
      outdent`
    #!${process.execPath}
    console.log("\\\\ no-deps-backslash \\\\");
  `,
    ),
  );

  await p.esy('install');
  await p.esy('build');

  const {stdout} = await p.esy('x test.cmd');
  expect(stdout.trim()).toEqual('\\ no-deps-backslash \\');
});
