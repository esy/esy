// @flow

const helpers = require('../test/helpers.js');

const {file, dir, packageJson} = helpers;

function makePackage(
  p,
  {
    name,
    dependencies = {},
    devDependencies = {},
  }: {
    name: string,
    dependencies?: {[name: string]: string},
    devDependencies?: {[name: string]: string},
  },
  ...items
) {
  return dir(
    name,
    packageJson({
      name: name,
      version: '1.0.0',
      license: 'MIT',
      esy: {
        buildsInSource: true,
        build: [helpers.buildCommand(p, '#{self.name}.js')],
        install: [
          `cp #{self.name}.cmd #{self.bin / self.name}.cmd`,
          `cp #{self.name}.js #{self.bin / self.name}.js`,
        ],
      },
      dependencies,
      devDependencies,
    }),
    helpers.dummyExecutable(name),
    ...items,
  );
}

describe('Projects with multiple sandboxes', function() {
  it('can build multiple sandboxes', async () => {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      file(
        'package.json',
        `
        {
          "esy": {},
          "dependencies": {"default-dep": "path:./default-dep"}
        }
        `,
      ),
      file(
        'package.custom.json',
        `
        {
          "esy": {},
          "dependencies": {"custom-dep": "path:./custom-dep"}
        }
        `,
      ),
      makePackage(p, {name: 'default-dep'}),
      makePackage(p, {name: 'custom-dep'}),
    );

    await p.esy('install');
    await p.esy('build');

    {
      const {stdout} = await p.esy('default-dep.cmd');
      expect(stdout.trim()).toBe('__default-dep__');
    }

    expect(p.esy('custom-dep')).rejects.toThrow();

    await p.esy('@package.custom.json install');
    await p.esy('@package.custom.json build');

    {
      const {stdout} = await p.esy('@package.custom.json custom-dep.cmd');
      expect(stdout.trim()).toBe('__custom-dep__');
    }

    expect(p.esy('@package.custom.json default-dep.cmd')).rejects.toThrow();

    {
      // .json extension could be dropped
      const {stdout} = await p.esy('@package.custom custom-dep.cmd');
      expect(stdout.trim()).toBe('__custom-dep__');
    }
  });
});
