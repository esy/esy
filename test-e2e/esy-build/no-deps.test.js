// @flow

const path = require('path');
const helpers = require('../test/helpers');
const {test, isWindows, isMacos, isLinux} = helpers;

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

describe(`'esy build': simple executable with no deps`, () => {
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

    test(
      'build-env',
      withProject(async function(p) {
        let winsysDir =
          process.platform === 'win32' ? [helpers.getWindowsSystemDirectory()] : [];
        const id = JSON.parse((await p.esy('build-plan')).stdout).id;
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
          cur__name: `no-deps`,
          cur__man: `${p.projectPath}/_esy/default/store/i/${id}/man`,
          cur__lib: `${p.projectPath}/_esy/default/store/i/${id}/lib`,
          cur__install: `${p.projectPath}/_esy/default/store/i/${id}`,
          cur__etc: `${p.projectPath}/_esy/default/store/i/${id}/etc`,
          cur__doc: `${p.projectPath}/_esy/default/store/i/${id}/doc`,
          cur__bin: `${p.projectPath}/_esy/default/store/i/${id}/bin`,
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
          OCAMLFIND_DESTDIR: `${p.projectPath}/_esy/default/store/i/${id}/lib`,
          DUNE_BUILD_DIR: `${p.projectPath}/_esy/default/store/b/${id}`,
        });
      }),
    );

    test.enableIf(isMacos || isLinux)(
      'macos || linux: build-env snapshot',
      withProject(async function(p) {
        const id = JSON.parse((await p.esy('build-plan')).stdout).id;
        const {stdout} = await p.esy('build-env');
        expect(p.normalizePathsForSnapshot(stdout, {id: id})).toMatchSnapshot();
      }),
    );

    test(
      'sandbox-env',
      withProject(async function(p) {
        const id = JSON.parse((await p.esy('build-plan')).stdout).id;
        const {stdout} = await p.esy('sandbox-env --json');
        const envpath = JSON.parse(stdout).PATH.split(path.delimiter);
        expect(
          envpath.includes(`${p.projectPath}/_esy/default/store/i/${id}/bin`),
        ).toBeTruthy();
      }),
    );

    test(
      'command-env',
      withProject(async function(p) {
        const id = JSON.parse((await p.esy('build-plan')).stdout).id;
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
          cur__name: `no-deps`,
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
      }),
    );
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
