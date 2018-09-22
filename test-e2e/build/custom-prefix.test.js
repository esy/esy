// @flow

const helpers = require('../test/helpers');

const fixture = [
  helpers.packageJson({
    name: 'custom-prefix',
    version: '1.0.0',
    esy: {
      build: [
        'cp #{self.name}.js #{self.target_dir / self.name}.js',
        helpers.buildCommand('#{self.target_dir / self.name}.js'),
      ],
      install: [
        'cp #{self.target_dir / self.name}.cmd #{self.bin / self.name}.cmd',
        'cp #{self.target_dir / self.name}.js #{self.bin / self.name}.js',
      ],
    },
  }),
  helpers.file('.esyrc', 'esy-prefix-path: ./store'),
  helpers.dummyExecutable('custom-prefix'),
];

it('Can be configured to build into a custom prefix (via .esyrc)', async () => {
  const p = await helpers.createTestSandbox(...fixture);

  await p.esy('build', {noEsyPrefix: true});

  const {stdout} = await p.esy('x custom-prefix.cmd', {noEsyPrefix: true});
  expect(stdout.trim()).toEqual('__custom-prefix__');
});
