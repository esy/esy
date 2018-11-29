// @flow

const helpers = require('../test/helpers');

const fixture = [];

describe('Allows deps to aughment $PATH', () => {
  it('package "dep" should be visible in all envs', async () => {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      helpers.packageJson({
        name: 'augment-path',
        version: '1.0.0',
        esy: {
          build: 'true',
        },
        dependencies: {
          dep: 'path:./dep',
        },
      }),
      helpers.dir(
        'dep',
        helpers.packageJson({
          name: 'dep',
          version: '1.0.0',
          esy: {
            // This installs executable into self.lib (and not self.bin which is
            // in $PATH by default) and then overrides $PATH by adding self.lib.
            //
            // That means dep.exe should still resolvable in $PATH.
            buildsInSource: true,
            build: [helpers.buildCommand(p, '#{self.name}.js')],
            install: [
              'cp #{self.name}.cmd #{self.lib / self.name}.cmd',
              'cp #{self.name}.js #{self.lib / self.name}.js',
            ],
            exportedEnv: {
              PATH: {
                val: '#{self.lib : $PATH}',
                scope: 'global',
              },
            },
          },
        }),
        helpers.dummyExecutable('dep'),
      ),
    );
    await p.esy('install');
    await p.esy('build');

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
  });
});
