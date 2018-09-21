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

    it('package "dep" should be visible in all envs', checkDepIsInEnv);
    it('should not rebuild dep with no changes', checkShouldNotRebuildIfNoChanges);
    it('should rebuild if file has been added', checkShouldRebuildOnChanges);
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

    it('package "dep" should be visible in all envs', checkDepIsInEnv);
    it('should not rebuild dep with no changes', checkShouldNotRebuildIfNoChanges);
    it('should rebuild if file has been added', checkShouldRebuildOnChanges);
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

    it('package "dep" should be visible in all envs', checkDepIsInEnv);
    it('should not rebuild dep with no changes', checkShouldNotRebuildIfNoChanges);
    it('should rebuild if file has been added', checkShouldRebuildOnChanges);
  });
});
