// @flow

const path = require('path');
const fs = require('fs');
const {promisify} = require('util');
const open = promisify(fs.open);
const close = promisify(fs.close);

const helpers = require('../test/helpers');
const {test, isWindows, isMacos, isLinux} = helpers;

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
      resolutions: {
        dep: 'link:./dep',
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
  ];
}

describe('Build with a linked dep', () => {
  describe('out of source build', () => {
    function withProject(assertions) {
      return async () => {
        const p = await helpers.createTestSandbox();
        await p.fixture(
          ...makeFixture(p, {
            build: [
              'cp #{self.root / self.name}.js #{self.target_dir / self.name}.js',
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

    it('package "dep" should be visible in all envs', withProject(async p => {
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
    }));

    test.enableIf(isMacos || isLinux)(
      'macos || linux: build-env snapshot',
      withProject(async function(p) {
        const id = JSON.parse((await p.esy('build-plan')).stdout).id;
        const depid = JSON.parse((await p.esy('build-plan -p dep')).stdout).id;
        const {stdout} = await p.esy('build-env');
        expect(p.normalizePathsForSnapshot(stdout, {id, depid})).toMatchSnapshot();
      }),
    );

    test.enableIf(isMacos || isLinux)(
      'macos || linux: build-env dep snapshot',
      withProject(async function(p) {
        const id = JSON.parse((await p.esy('build-plan -p dep')).stdout).id;
        const {stdout} = await p.esy('build-env -p dep');
        expect(p.normalizePathsForSnapshot(stdout, {id})).toMatchSnapshot();
      }),
    );
  });

  describe('in source build', () => {
    function withProject(assertions) {
      return async () => {
        const p = await helpers.createTestSandbox();
        await p.fixture(
          ...makeFixture(p, {
            buildsInSource: true,
            build: [helpers.buildCommand(p, '#{self.root / self.name}.js')],
            install: [
              `cp #{self.root / self.name}.cmd #{self.bin / self.name}.cmd`,
              `cp #{self.root / self.name}.js #{self.bin / self.name}.js`,
            ],
          }),
        );
        await p.esy('install');
        await p.esy('build');
        await assertions(p);
      };
    }

    it('package "dep" should be visible in all envs', withProject(async p => {
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
    }));
  });

  describe('_build build', () => {
    function withProject(assertions) {
      return async () => {
        const p = await helpers.createTestSandbox();
        await p.fixture(
          ...makeFixture(p, {
            buildsInSource: '_build',
            build: [
              "mkdir -p #{self.root / '_build'}",
              "cp #{self.root / self.name}.js #{self.root / '_build' / self.name}.js",
              helpers.buildCommand(p, "#{self.root / '_build' / self.name}.js"),
            ],
            install: [
              `cp #{self.root / '_build' / self.name}.cmd #{self.bin / self.name}.cmd`,
              `cp #{self.root / '_build' / self.name}.js #{self.bin / self.name}.js`,
            ],
          }),
        );
        await p.esy('install');
        await p.esy('build');
        await assertions(p);
      };
    }

    it('package "dep" should be visible in all envs', withProject(async p => {
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
    }));
  });

  describe('out of source build with "buildDev" in dep', () => {
    function withProject(assertions) {
      return async () => {
        const p = await helpers.createTestSandbox();
        await p.fixture(
          ...makeFixture(p, {
            build: [
              'cp #{self.root / self.name}.js #{self.target_dir / self.name}.js',
              helpers.buildCommand(p, '#{self.target_dir / self.name}.js'),
            ],
            // set it to false so we fail if it's executed
            buildDev: 'false',
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

    it('package "dep" should be visible in all envs', withProject(async p => {
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
    }));
  });

});
