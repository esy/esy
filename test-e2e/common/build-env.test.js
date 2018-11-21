// @flow

const path = require('path');
const fs = require('fs-extra');

const {createTestSandbox, promiseExec, skipSuiteOnWindows} = require('../test/helpers');
const fixture = require('./fixture.js');

skipSuiteOnWindows('#301');

describe('esy build-env', () => {
  it('generates an environment as bash source', async () => {
    const p = await createTestSandbox();
    await p.fixture(...fixture.makeSimpleProject(p));

    await p.esy('install');
    await p.esy('build');

    const env = (await p.esy('build-env')).stdout;

    await fs.writeFile(path.join(p.projectPath, 'build-env'), env);

    await expect(
      promiseExec('. ./build-env && dep.cmd', {
        cwd: p.projectPath,
      }),
    ).resolves.toEqual({stdout: '__dep__\n', stderr: ''});

    await expect(
      promiseExec('. ./build-env && devDep.cmd', {
        cwd: p.projectPath,
      }),
    ).rejects.toThrow();
  });

  it('generates an environment in JSON', async () => {
    const p = await createTestSandbox();
    await p.fixture(...fixture.makeSimpleProject(p));

    await p.esy('install');
    await p.esy('build');

    const env = JSON.parse((await p.esy('build-env --json')).stdout);

    expect(env.cur__version).toBe('1.0.0');
    expect(env.cur__name).toBe('simple-project');
    expect(env.cur__toplevel).toBeTruthy();
    expect(env.cur__target_dir).toBeTruthy();
    expect(env.cur__stublibs).toBeTruthy();
    expect(env.cur__share).toBeTruthy();
    expect(env.cur__sbin).toBeTruthy();
    expect(env.cur__root).toBeTruthy();

    expect(env.cur__original_root).toBeTruthy();
    expect(env.cur__original_root).toBe(p.projectPath);

    expect(env.cur__man).toBeTruthy();
    expect(env.cur__lib).toBeTruthy();
    expect(env.cur__install).toBeTruthy();
    expect(env.cur__etc).toBeTruthy();
    expect(env.cur__doc).toBeTruthy();
    expect(env.cur__bin).toBeTruthy();
    expect(env.SHELL).toBeTruthy();
    expect(env.PATH).toBeTruthy();
    expect(env.OCAMLPATH).toBeTruthy();
    expect(env.OCAMLFIND_LDCONF).toBeTruthy();
    expect(env.OCAMLFIND_DESTDIR).toBeTruthy();
    expect(env.MAN_PATH).toBeTruthy();
    expect(env.CAML_LD_LIBRARY_PATH).toBeTruthy();

    expect(env.DUNE_BUILD_DIR).toBeTruthy();
    expect(env.DUNE_BUILD_DIR).toBe(env.cur__target_dir);

    // build env
    expect(env.root__build).toBe('root__build__value');

    // exported env isn't present in the build env of the same package
    expect(env.root__local).toBe(undefined);
    expect(env.root__global).toBe(undefined);

    // deps are present in build env
    expect(env.dep__local).toBe('dep__local__value');
    expect(env.dep__global).toBe('dep__global__value');

    // but only direct deps contribute local exports
    expect(env.depOfDep__local).toBe(undefined);
    expect(env.depOfDep__global).toBe('depOfDep__global__value');

    // dev deps are not present in build env
    expect(env.devDep__local).toBe(undefined);
    expect(env.devDep__global).toBe(undefined);
  });

  it('allows to query build env for a dep (by name)', async () => {
    const p = await createTestSandbox();
    await p.fixture(...fixture.makeSimpleProject(p));

    await p.esy('install');
    await p.esy('build');

    const env = JSON.parse((await p.esy('build-env --json dep')).stdout);
    expect(env.cur__name).toBe('dep');
  });

  it('allows to query build env for a dep (by name, version)', async () => {
    const p = await createTestSandbox();
    await p.fixture(...fixture.makeSimpleProject(p));

    await p.esy('install');
    await p.esy('build');

    const env = JSON.parse((await p.esy('build-env --json dep@1.0.0')).stdout);
    expect(env.cur__name).toBe('dep');
  });
});
