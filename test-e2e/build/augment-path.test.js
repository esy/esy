// @flow

const helpers = require('../test/helpers');

const fixture = [
  helpers.packageJson({
    name: 'augment-path',
    version: '1.0.0',
    esy: {
      build: 'true',
    },
    dependencies: {
      dep: '*',
    },
  }),
  helpers.dir(
    ['node_modules', 'dep'],
    helpers.packageJson({
      name: 'dep',
      version: '1.0.0',
      esy: {
        // This installs executable into self.lib (and not self.bin which is
        // in $PATH by default) and then overrides $PATH by adding self.lib.
        //
        // That means dep.exe should still resolvable in $PATH.
        buildsInSource: true,
        build: 'chmod +x #{self.name}.exe',
        install: 'cp #{self.name}.exe #{self.lib / self.name}.exe',
        exportedEnv: {
          PATH: {
            val: '#{self.lib : $PATH}',
            scope: 'global',
          },
        },
      },
      '_esy.source': 'path:.',
    }),
    helpers.dummyExecutable('dep'),
  ),
];

describe('Allows deps to aughment $PATH', () => {
  it('package "dep" should be visible in all envs', async () => {
    const p = await helpers.createTestSandbox(...fixture);
    await p.esy('build');

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
  });
});
