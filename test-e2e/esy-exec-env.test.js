// @flow

const path = require('path');
const fs = require('fs-extra');

const {createTestSandbox, promiseExec, skipSuiteOnWindows} = require('./test/helpers');
const fixture = require('./common/fixture.js');

// This test is not expected to work on Windows
// because it command-env works only with bash
// While it's a feature that may help users
// with MSYS2 or Cygwin, we don't have a validated
// usecase, where a workaround is not possible.
skipSuiteOnWindows('#301');

describe('esy exec-env', () => {
  it('generates env as a bash source', async () => {
    const p = await createTestSandbox();
    await p.fixture(...fixture.makeSimpleProject(p));
    await p.esy('install');
    await p.esy('build');

    const env = (await p.esy('exec-env')).stdout;

    await fs.writeFile(path.join(p.projectPath, 'exec-env'), env);

    await expect(
      promiseExec('. ./exec-env && dep.cmd', {
        cwd: p.projectPath,
      }),
    ).resolves.toEqual({stdout: '__dep__\n', stderr: ''});

    await expect(
      promiseExec('. ./exec-env && devDep.cmd', {
        cwd: p.projectPath,
      }),
    ).resolves.toEqual({stdout: '__devDep__\n', stderr: ''});
  });

  it('generates env as JSON', async () => {
    const p = await createTestSandbox();
    await p.fixture(...fixture.makeSimpleProject(p));
    await p.esy('install');
    await p.esy('build');

    const env = JSON.parse((await p.esy('exec-env --json')).stdout);

    expect(env.PATH).toBeTruthy();
    expect(env.OCAMLPATH).toBeTruthy();
    expect(env.MAN_PATH).toBeTruthy();
    expect(env.CAML_LD_LIBRARY_PATH).toBeTruthy();

    // build env isn't present in sandbox env
    expect(env.root__build).toBe(undefined);

    // exported env is present in the sandbox env
    expect(env.root__local).toBe('root__local__value');
    expect(env.root__global).toBe('root__global__value');

    // deps are present in command env
    expect(env.dep__local).toBe('dep__local__value');
    expect(env.dep__global).toBe('dep__global__value');

    // but only direct deps contribute local exports
    expect(env.depOfDep__local).toBe(undefined);
    expect(env.depOfDep__global).toBe('depOfDep__global__value');

    // dev deps are present in command env
    expect(env.devDep__local).toBe('devDep__local__value');
    expect(env.devDep__global).toBe('devDep__global__value');
  });
});
