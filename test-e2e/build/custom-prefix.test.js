// @flow

const helpers = require('../test/helpers');

const fixture = [
  helpers.packageJson({
    name: 'custom-prefix',
    version: '1.0.0',
    esy: {
      build: [
        'cp #{self.name}.exe #{self.target_dir / self.name}.exe',
        'chmod +x #{self.target_dir / self.name}.exe',
      ],
      install: ['cp #{self.target_dir / self.name}.exe #{self.bin / self.name}.exe'],
    },
  }),
  helpers.file('.esyrc', 'esy-prefix-path: ./store'),
  helpers.dummyExecutable('custom-prefix'),
];

it('Can be configured to build into a custom prefix (via .esyrc)', async () => {
  const p = await helpers.createTestSandbox(...fixture);

  await p.esy('build', {noEsyPrefix: true});

  const {stdout} = await p.esy('x custom-prefix.exe', {noEsyPrefix: true});
  expect(stdout.trim()).toEqual('__custom-prefix__');
});
