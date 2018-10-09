// @flow

const helpers = require('../test/helpers');

function makeFixture(p, buildDep) {
  return [
    helpers.packageJson({
      name: 'no-deps',
      version: '1.0.0',
      esy: buildDep,
    }),
    helpers.dummyExecutable('no-deps'),
  ];
}

describe('Build simple executable with no deps', () => {
  async function checkIsInEnv(p) {
    const {stdout} = await p.esy('x no-deps.cmd');
    expect(stdout.trim()).toEqual('__no-deps__');
  }

  describe('out of source build', () => {
    function withProject(assertions) {
      return async () => {
        const p = await helpers.createTestSandbox();
        p.fixture(
          ...makeFixture(p, {
            build: [
              ['cp', '#{self.name}.js', '#{self.target_dir / self.name}.js'],
              helpers.buildCommand(p, '#{self.target_dir / self.name}.js'),
            ],
            install: [
              `cp #{self.target_dir / self.name}.cmd #{self.bin / self.name}.cmd`,
              `cp #{self.target_dir / self.name}.js #{self.bin / self.name}.js`,
            ],
          }),
        );
        await p.esy('install');
        await p.esy('build');
        await assertions(p);
      };
    }

    test('executable is available in sandbox env', withProject(checkIsInEnv));
  });

  describe('in source build', () => {
    function withProject(assertions) {
      return async () => {
        const p = await helpers.createTestSandbox();
        p.fixture(
          ...makeFixture(p, {
            buildsInSource: true,
            build: [helpers.buildCommand(p, '#{self.name}.js')],
            install: [
              `cp #{self.name}.cmd #{self.bin / self.name}.cmd`,
              `cp #{self.name}.js #{self.bin / self.name}.js`,
            ],
          }),
        );
        await p.esy('install');
        await p.esy('build');
        await assertions(p);
      };
    }
    test('executable is available in sandbox env', withProject(checkIsInEnv));
  });

  describe('_build build', () => {
    function withProject(assertions) {
      return async () => {
        const p = await helpers.createTestSandbox();
        p.fixture(
          ...makeFixture(p, {
            buildsInSource: '_build',
            build: [
              'mkdir -p _build',
              'cp #{self.name}.js _build/#{self.name}.js',
              helpers.buildCommand(p, '_build/#{self.name}.js'),
            ],
            install: [
              `cp _build/#{self.name}.cmd #{self.bin / self.name}.cmd`,
              `cp _build/#{self.name}.js #{self.bin / self.name}.js`,
            ],
          }),
        );
        await p.esy('install');
        await p.esy('build');
        await assertions(p);
      };
    }
    test('executable is available in sandbox env', withProject(checkIsInEnv));
  });
});
