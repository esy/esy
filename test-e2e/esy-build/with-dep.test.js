// @flow

const path = require('path');
const helpers = require('../test/helpers');
const {test, isWindows, isMacos} = helpers;

function makeFixture(p, buildDep) {
  return [
    helpers.packageJson({
      name: 'withDep',
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
        esy: buildDep,
        '_esy.source': 'path:./',
      }),
      helpers.dummyExecutable('dep'),
    ),
  ];
}

describe('Build with dep', () => {
  let winsysDir =
    process.platform === 'win32' ? [helpers.getWindowsSystemDirectory()] : [];

  async function checkDepIsInEnv(p) {
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

    it('makes dep available in envs', withProject(checkDepIsInEnv));

    test(
      'build-env',
      withProject(async function(p) {
        const id = JSON.parse((await p.esy('build-plan')).stdout).id;
        const depId = JSON.parse((await p.esy('build-plan dep')).stdout).id;

        const {stdout} = await p.esy('build-env --json');
        const env = JSON.parse(stdout);
        expect(env).toMatchObject({
          cur__version: '1.0.0',
          cur__toplevel: `${p.projectPath}/_esy/default/store/i/${id}/toplevel`,
          cur__target_dir: `${p.projectPath}/_esy/default/store/b/${id}`,
          cur__stublibs: `${p.projectPath}/_esy/default/store/i/${id}/stublibs`,
          cur__share: `${p.projectPath}/_esy/default/store/i/${id}/share`,
          cur__sbin: `${p.projectPath}/_esy/default/store/i/${id}/sbin`,
          cur__root: `${p.projectPath}`,
          cur__original_root: `${p.projectPath}`,
          cur__name: `withDep`,
          cur__man: `${p.projectPath}/_esy/default/store/i/${id}/man`,
          cur__lib: `${p.projectPath}/_esy/default/store/i/${id}/lib`,
          cur__install: `${p.projectPath}/_esy/default/store/i/${id}`,
          cur__etc: `${p.projectPath}/_esy/default/store/i/${id}/etc`,
          cur__doc: `${p.projectPath}/_esy/default/store/i/${id}/doc`,
          cur__bin: `${p.projectPath}/_esy/default/store/i/${id}/bin`,
          PATH: [
            `${p.esyStorePath}/i/${depId}/bin`,
            ``,
            `/usr/local/bin`,
            `/usr/bin`,
            `/bin`,
            `/usr/sbin`,
            `/sbin`,
            ...winsysDir,
          ].join(path.delimiter),
          OCAMLFIND_LDCONF: `ignore`,
          OCAMLFIND_DESTDIR: `${p.projectPath}/_esy/default/store/i/${id}/lib`,
          DUNE_BUILD_DIR: `${p.projectPath}/_esy/default/store/b/${id}`,
        });
      }),
    );

    test.enableIf(isMacos)(
      'macos: build-env snapshot',
      withProject(async function(p) {
        const id = JSON.parse((await p.esy('build-plan')).stdout).id;
        const {stdout} = await p.esy('build-env');
        expect(p.normalizePathsForSnapshot(stdout, {id: id})).toMatchSnapshot();
      }),
    );

    test(
      'build-env dep',
      withProject(async function(p) {
        const id = JSON.parse((await p.esy('build-plan')).stdout).id;
        const depId = JSON.parse((await p.esy('build-plan dep')).stdout).id;

        const {stdout} = await p.esy('build-env --json dep');
        const env = JSON.parse(stdout);
        expect(env).toMatchObject({
          cur__version: '1.0.0',
          cur__toplevel: `${p.esyStorePath}/s/${depId}/toplevel`,
          cur__target_dir: `${p.esyStorePath}/b/${depId}`,
          cur__stublibs: `${p.esyStorePath}/s/${depId}/stublibs`,
          cur__share: `${p.esyStorePath}/s/${depId}/share`,
          cur__sbin: `${p.esyStorePath}/s/${depId}/sbin`,
          cur__name: `dep`,
          cur__man: `${p.esyStorePath}/s/${depId}/man`,
          cur__lib: `${p.esyStorePath}/s/${depId}/lib`,
          cur__install: `${p.esyStorePath}/s/${depId}`,
          cur__etc: `${p.esyStorePath}/s/${depId}/etc`,
          cur__doc: `${p.esyStorePath}/s/${depId}/doc`,
          cur__bin: `${p.esyStorePath}/s/${depId}/bin`,
          PATH: [
            ``,
            `/usr/local/bin`,
            `/usr/bin`,
            `/bin`,
            `/usr/sbin`,
            `/sbin`,
            ...winsysDir,
          ].join(path.delimiter),
          OCAMLFIND_LDCONF: `ignore`,
          OCAMLFIND_DESTDIR: `${p.esyStorePath}/s/${depId}/lib`,
          DUNE_BUILD_DIR: `${p.esyStorePath}/b/${depId}`,
        });
      }),
    );

    test.enableIf(isMacos)(
      'macos: build-env dep snapshot',
      withProject(async function(p) {
        const id = JSON.parse((await p.esy('build-plan dep')).stdout).id;
        const {stdout} = await p.esy('build-env dep');
        expect(p.normalizePathsForSnapshot(stdout, {id: id})).toMatchSnapshot();
      }),
    );

    test(
      'sandbox-env',
      withProject(async function(p) {
        const id = JSON.parse((await p.esy('build-plan')).stdout).id;
        const depId = JSON.parse((await p.esy('build-plan dep')).stdout).id;
        const {stdout} = await p.esy('sandbox-env --json');
        const envpath = JSON.parse(stdout).PATH.split(path.delimiter);
        expect(
          envpath.includes(`${p.projectPath}/_esy/default/store/i/${id}/bin`),
        ).toBeTruthy();
        expect(envpath.includes(`${p.esyStorePath}/i/${depId}/bin`)).toBeTruthy();
      }),
    );

    test(
      'command-env',
      withProject(async function(p) {
        const id = JSON.parse((await p.esy('build-plan')).stdout).id;
        const depId = JSON.parse((await p.esy('build-plan dep')).stdout).id;
        const {stdout} = await p.esy('command-env --json');
        const env = JSON.parse(stdout);
        expect(env).toMatchObject({
          cur__version: '1.0.0',
          cur__toplevel: `${p.projectPath}/_esy/default/store/i/${id}/toplevel`,
          cur__target_dir: `${p.projectPath}/_esy/default/store/b/${id}`,
          cur__stublibs: `${p.projectPath}/_esy/default/store/i/${id}/stublibs`,
          cur__share: `${p.projectPath}/_esy/default/store/i/${id}/share`,
          cur__sbin: `${p.projectPath}/_esy/default/store/i/${id}/sbin`,
          cur__root: `${p.projectPath}`,
          cur__original_root: `${p.projectPath}`,
          cur__name: `withDep`,
          cur__man: `${p.projectPath}/_esy/default/store/i/${id}/man`,
          cur__lib: `${p.projectPath}/_esy/default/store/i/${id}/lib`,
          cur__install: `${p.projectPath}/_esy/default/store/i/${id}`,
          cur__etc: `${p.projectPath}/_esy/default/store/i/${id}/etc`,
          cur__doc: `${p.projectPath}/_esy/default/store/i/${id}/doc`,
          cur__bin: `${p.projectPath}/_esy/default/store/i/${id}/bin`,
          OCAMLFIND_LDCONF: `ignore`,
          OCAMLFIND_DESTDIR: `${p.projectPath}/_esy/default/store/i/${id}/lib`,
          DUNE_BUILD_DIR: `${p.projectPath}/_esy/default/store/b/${id}`,
        });
        const envpath = env.PATH.split(path.delimiter);
        expect(envpath.includes(`${p.esyStorePath}/i/${depId}/bin`)).toBeTruthy();
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

    it('makes dep available in envs', withProject(checkDepIsInEnv));
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
    it('makes dep available in envs', withProject(checkDepIsInEnv));
  });
});
