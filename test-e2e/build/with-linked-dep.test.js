// @flow

const path = require('path');
const fs = require('fs');
const {promisify} = require('util');
const open = promisify(fs.open);
const close = promisify(fs.close);

const helpers = require('../test/helpers');

function makeFixture(p, buildDep) {
  return [
    helpers.packageJson({
      name: 'with-linked-dep-_build',
      version: '1.0.0',
      esy: {
        build: 'true',
      },
      dependencies: {
        dep: '*',
      },
    }),
    helpers.dir(
      'dep',
      helpers.packageJson({
        name: 'dep',
        version: '1.0.0',
        esy: buildDep,
      }),
      helpers.dummyExecutable('dep'),
    ),
    helpers.dir(
      'node_modules',
      helpers.dir(
        'dep',
        helpers.file(
          '_esylink',
          JSON.stringify({
            source: `link:${path.join(p.projectPath, 'dep')}`,
          }),
        ),
        helpers.symlink('package.json', '../../dep/package.json'),
      ),
    ),
  ];
}

describe('Build with a linked dep', () => {
  let p;

  async function checkDepIsInEnv() {
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
  }

  async function checkShouldNotRebuildIfNoChanges() {
    const noOpBuild = await p.esy('build');
    expect(noOpBuild.stdout).not.toEqual(
      expect.stringMatching('Building dep@1.0.0: starting'),
    );
  }

  async function checkShouldRebuildOnChanges() {
    await open(path.join(p.projectPath, 'dep', 'dummy'), 'w').then(close);

    const {stdout} = await p.esy('build');
    // TODO: why is this on stderr?
    expect(stdout).toEqual(expect.stringMatching('Building dep@1.0.0: starting'));
  }

  describe('out of source build', () => {
    beforeEach(async () => {
      p = await helpers.createTestSandbox();
      await p.fixture(
        ...makeFixture(p, {
          build: [
            'cp #{self.root / self.name}.js #{self.target_dir / self.name}.js',
            helpers.buildCommand('#{self.target_dir / self.name}.js'),
          ],
          install: [
            `cp #{self.target_dir / self.name}.cmd #{self.bin / self.name}.cmd`,
            `cp #{self.target_dir / self.name}.js #{self.bin / self.name}.js`,
          ],
        }),
      );
      await p.esy('build');
    });

    it('package "dep" should be visible in all envs', checkDepIsInEnv);
    it('should not rebuild dep with no changes', checkShouldNotRebuildIfNoChanges);
    it('should rebuild if file has been added', checkShouldRebuildOnChanges);
  });

  describe('in source build', () => {
    beforeEach(async () => {
      p = await helpers.createTestSandbox();
      await p.fixture(
        ...makeFixture(p, {
          buildsInSource: true,
          build: helpers.buildCommand('#{self.root / self.name}.js'),
          install: [
            `cp #{self.root / self.name}.cmd #{self.bin / self.name}.cmd`,
            `cp #{self.root / self.name}.js #{self.bin / self.name}.js`,
          ],
        }),
      );
      await p.esy('build');
    });

    it('package "dep" should be visible in all envs', checkDepIsInEnv);
    it('should not rebuild dep with no changes', checkShouldNotRebuildIfNoChanges);
    it('should rebuild if file has been added', checkShouldRebuildOnChanges);
  });

  describe('_build build', () => {
    beforeEach(async () => {
      p = await helpers.createTestSandbox();
      await p.fixture(
        ...makeFixture(p, {
          buildsInSource: '_build',
          build: [
            "mkdir -p #{self.root / '_build'}",
            "cp #{self.root / self.name}.js #{self.root / '_build' / self.name}.js",
            helpers.buildCommand("#{self.root / '_build' / self.name}.js"),
          ],
          install: [
            `cp #{self.root / '_build' / self.name}.cmd #{self.bin / self.name}.cmd`,
            `cp #{self.root / '_build' / self.name}.js #{self.bin / self.name}.js`,
          ],
        }),
      );
      await p.esy('build');
    });

    it('package "dep" should be visible in all envs', checkDepIsInEnv);
    it('should not rebuild dep with no changes', checkShouldNotRebuildIfNoChanges);
    it('should rebuild if file has been added', checkShouldRebuildOnChanges);
  });
});
