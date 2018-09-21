// @flow

const helpers = require('../test/helpers');

function makeFixture(p, buildDep) {
  return [
    helpers.packageJson({
      name: 'withDep',
      version: '1.0.0',
      esy: {
        build: 'true',
      },
      dependencies: {
        dep: '*',
      },
    }),
    helpers.dir(
      'node_modules',
      helpers.dir(
        'dep',
        helpers.packageJson({
          name: 'dep',
          version: '1.0.0',
          esy: buildDep,
          '_esy.source': 'path:./',
        }),
        helpers.dummyExecutable('dep'),
      ),
    ),
  ];
}

describe('Build with dep', () => {
  let p;

  async function checkDepIsInEnv() {
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
  }

  describe('out of source build', () => {
    beforeAll(async () => {
      p = await helpers.createTestSandbox();
      await p.fixture(
        ...makeFixture(p, {
          build: [
            'cp #{self.root / self.name}.exe #{self.target_dir / self.name}.exe',
            'chmod +x #{self.target_dir / self.name}.exe',
          ],
          install: [`cp #{self.target_dir / self.name}.exe #{self.bin / self.name}.exe`],
        }),
      );
      await p.esy('build');
    });

    it('makes dep available in envs', checkDepIsInEnv);
  });

  describe('in source build', () => {
    beforeAll(async () => {
      p = await helpers.createTestSandbox();
      await p.fixture(
        ...makeFixture(p, {
          buildsInSource: true,
          build: [
            'touch #{self.root / self.name}.exe',
            'chmod +x #{self.root / self.name}.exe',
          ],
          install: [`cp #{self.root / self.name}.exe #{self.bin / self.name}.exe`],
        }),
      );
      await p.esy('build');
    });

    it('makes dep available in envs', checkDepIsInEnv);
  });

  describe('_build build', () => {
    beforeAll(async () => {
      p = await helpers.createTestSandbox();
      await p.fixture(
        ...makeFixture(p, {
          buildsInSource: '_build',
          build: [
            "mkdir -p #{self.root / '_build'}",
            "cp #{self.root / self.name}.exe #{self.root / '_build' / self.name}.exe",
            "chmod +x #{self.root / '_build' / self.name}.exe",
          ],
          install: [
            `cp #{self.root / '_build' / self.name}.exe #{self.bin / self.name}.exe`,
          ],
        }),
      );
      await p.esy('build');
    });

    it('makes dep available in envs', checkDepIsInEnv);
  });
});
