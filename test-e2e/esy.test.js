// @flow

const helpers = require('./test/helpers');
const {file, dir, packageJson, dummyExecutable} = helpers;

it('Build - default command', async () => {
  let p = await helpers.createTestSandbox();

  await p.fixture(
    packageJson({
      name: 'default-command',
      version: '1.0.0',
      esy: {
        build: 'true',
      },
      dependencies: {
        dep: '*',
      },
      resolutions: {
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
              '#{self.original_root / self.name}.js',
              '#{self.target_dir / self.name}.js',
            ],
            helpers.buildCommand(p, '#{self.target_dir / self.name}.js'),
          ],
          install: [
            ['cp', '#{self.target_dir / self.name}.cmd', '#{self.bin / self.name}.cmd'],
            ['cp', '#{self.target_dir / self.name}.js', '#{self.bin / self.name}.js'],
          ],
        },
        '_esy.source': 'path:./',
      }),
      dummyExecutable('dep'),
    ),
  );

  await p.esy();

  const dep = await p.esy('dep.cmd');

  expect(dep.stdout.trim()).toEqual('__dep__');
});
