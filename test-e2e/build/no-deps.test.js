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
  let p;

  async function checkIsInEnv() {
    const {stdout} = await p.esy('x no-deps.exe');
    expect(stdout.trim()).toEqual('__no-deps__');
  }

  describe('out of source build', () => {
    beforeAll(async () => {
      p = await helpers.createTestSandbox();
      p.fixture(
        ...makeFixture(p, {
          build: [
            'cp #{self.name}.exe #{self.target_dir / self.name}.exe',
            'chmod +x #{self.target_dir / self.name}.exe',
          ],
          install: [`cp #{self.target_dir / self.name}.exe #{self.bin / self.name}.exe`],
        }),
      );
      await p.esy('build');
    });
    test('executable is available in sandbox env', checkIsInEnv);
  });

  describe('in source build', () => {
    beforeAll(async () => {
      p = await helpers.createTestSandbox();
      p.fixture(
        ...makeFixture(p, {
          buildsInSource: true,
          build: ['touch #{self.name}.exe', 'chmod +x #{self.name}.exe'],
          install: [`cp #{self.name}.exe #{self.bin / self.name}.exe`],
        }),
      );
      await p.esy('build');
    });
    test('executable is available in sandbox env', checkIsInEnv);
  });

  describe('_build build', () => {
    beforeAll(async () => {
      p = await helpers.createTestSandbox();
      p.fixture(
        ...makeFixture(p, {
          buildsInSource: '_build',
          build: [
            'mkdir -p _build',
            'cp #{self.name}.exe _build/#{self.name}.exe',
            'chmod +x _build/#{self.name}.exe',
          ],
          install: [`cp _build/#{self.name}.exe #{self.bin / self.name}.exe`],
        }),
      );
      await p.esy('build');
    });
    test('executable is available in sandbox env', checkIsInEnv);
  });
});
