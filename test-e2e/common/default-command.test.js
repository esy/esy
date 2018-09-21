// @flow

const helpers = require('../test/helpers');
const {file, dir, packageJson, dummyExecutable} = helpers;

helpers.skipSuiteOnWindows('Needs esyi to work');

const fixture = [
  packageJson({
    name: 'default-command',
    version: '1.0.0',
    esy: {
      build: 'true',
    },
    dependencies: {
      dep: 'link:./dep',
    },
  }),
  dir(
    'dep',
    packageJson({
      name: 'dep',
      version: '1.0.0',
      esy: {
        build: [
          [
            'cp',
            '#{self.original_root / self.name}.exe',
            '#{self.target_dir / self.name}.exe',
          ],
          ['chmod', '+x', '#{self.target_dir / self.name}.exe'],
        ],
        install: [
          ['cp', '#{self.target_dir / self.name}.exe', '#{self.bin / self.name}.exe'],
        ],
      },
      '_esy.source': 'path:./',
    }),
    dummyExecutable('dep'),
  ),
];

it('Build - default command', async () => {
  let p = await helpers.createTestSandbox(...fixture);
  await p.esy();

  const dep = await p.esy('dep.exe');

  expect(dep.stdout.trim()).toEqual('__dep__');
});
