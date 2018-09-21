// @flow

const helpers = require('../test/helpers');

helpers.skipSuiteOnWindows();

const fixture = [
  helpers.packageJson({
    name: 'creates-symlinks',
    version: '1.0.0',
    esy: {
      buildsInSource: true,
      build: 'chmod +x #{self.name}.exe',
      install: [
        'cp #{self.name}.exe #{self.lib / self.name}.exe',
        'ln -s #{self.lib / self.name}.exe #{self.bin / self.name}.exe',
      ],
    },
    dependencies: {
      dep: '*',
    },
  }),
  helpers.dummyExecutable('creates-symlinks'),
  helpers.dir(
    ['node_modules', 'dep'],
    helpers.packageJson({
      name: 'dep',
      version: '1.0.0',
      license: 'MIT',
      esy: {
        buildsInSource: true,
        build: 'chmod +x #{self.name}.exe',
        install: [
          'cp #{self.name}.exe #{self.lib / self.name}.exe',
          'ln -s #{self.lib / self.name}.exe #{self.bin / self.name}.exe',
        ],
      },
      '_esy.source': 'path:.',
    }),
    helpers.dummyExecutable('dep'),
  ),
];

it('Correctly handles symlinks within the installation', async () => {
  const p = await helpers.createTestSandbox(...fixture);

  await p.esy('build');

  const expecting = expect.stringMatching('__dep__');

  {
    const {stdout} = await p.esy('dep.exe');
    expect(stdout.trim()).toEqual('__dep__');
  }

  {
    const {stdout} = await p.esy('b dep.exe');
    expect(stdout.trim()).toEqual('__dep__');
  }

  {
    const {stdout} = await p.esy('x dep.exe');
    expect(stdout.trim()).toEqual('__dep__');
  }

  {
    let {stdout} = await p.esy('x creates-symlinks.exe');
    expect(stdout.trim()).toEqual('__creates-symlinks__');
  }
});
