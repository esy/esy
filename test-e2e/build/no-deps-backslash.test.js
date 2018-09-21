// @flow

const outdent = require('outdent');
const helpers = require('../test/helpers');

const fixture = [
  helpers.packageJson({
    name: 'no-deps-backslash',
    version: '1.0.0',
    license: 'MIT',
    esy: {
      build: [
        ['cp', '#{self.root /}test.exe', '#{self.target_dir /}test.exe'],
        ['chmod', '+x', '#{self.target_dir /}test.exe'],
      ],
      install: [['cp', '#{self.target_dir /}test.exe', '#{self.bin /}test.exe']],
    },
  }),
  helpers.file(
    'test.exe',
    outdent`
    #!${process.execPath}
    console.log("\\\\ no-deps-backslash \\\\");
  `,
  ),
];

it('Build - no deps backslash', async () => {
  const p = await helpers.createTestSandbox(...fixture);

  await p.esy('build');

  const {stdout} = await p.esy('x test.exe');
  expect(stdout.trim()).toEqual('\\ no-deps-backslash \\');
});
