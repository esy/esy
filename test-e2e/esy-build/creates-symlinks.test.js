// @flow

const helpers = require('../test/helpers');

helpers.skipSuiteOnWindows();

it('Correctly handles symlinks within the installation', async () => {
  const p = await helpers.createTestSandbox();

  await p.fixture(
    helpers.packageJson({
      name: 'creates-symlinks',
      version: '1.0.0',
      esy: {
        buildsInSource: true,
        build: [helpers.buildCommand(p, '#{self.name}.js')],
        install: [
          'cp #{self.name}.cmd #{self.lib / self.name}.cmd',
          'cp #{self.name}.js #{self.lib / self.name}.js',
          'ln -s #{self.lib / self.name}.cmd #{self.bin / self.name}.cmd',
        ],
      },
      dependencies: {
        dep: 'path:./dep',
      },
    }),
    helpers.dummyExecutable('creates-symlinks'),
    helpers.dir(
      'dep',
      helpers.packageJson({
        name: 'dep',
        version: '1.0.0',
        license: 'MIT',
        esy: {
          buildsInSource: true,
          build: [helpers.buildCommand(p, '#{self.name}.js')],
          install: [
            'cp #{self.name}.cmd #{self.lib / self.name}.cmd',
            'cp #{self.name}.js #{self.lib / self.name}.js',
            'ln -s #{self.lib / self.name}.cmd #{self.bin / self.name}.cmd',
          ],
        },
        '_esy.source': 'path:.',
      }),
      helpers.dummyExecutable('dep'),
    ),
  );

  await p.esy('install');
  await p.esy('build');

  const expecting = expect.stringMatching('__dep__');

  {
    const {stdout} = await p.esy('dep.cmd');
    expect(stdout.trim()).toEqual('__dep__');
  }

  {
    const {stdout} = await p.esy('b dep.cmd');
    expect(stdout.trim()).toEqual('__dep__');
  }

  {
    const {stdout} = await p.esy('x dep.cmd');
    expect(stdout.trim()).toEqual('__dep__');
  }

  {
    let {stdout} = await p.esy('x creates-symlinks.cmd');
    expect(stdout.trim()).toEqual('__creates-symlinks__');
  }
});
