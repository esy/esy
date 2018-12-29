// @flow

const os = require('os');
const path = require('path');
const del = require('del');
const fs = require('fs-extra');

const {createTestSandbox, skipSuiteOnWindows} = require('../test/helpers');
const fixture = require('./fixture.js');

skipSuiteOnWindows();

it('Common - esy prefix via esyrc', async () => {
  const tmp = process.platform === 'win32' ? os.tmpdir() : '/tmp';
  const tmpPath = await fs.mkdtemp(path.join(tmp, 'XXXX'));
  const customEsyPrefix = path.join(tmpPath, 'prefix');

  const p = await createTestSandbox();
  await p.fixture(...fixture.makeSimpleProject(p));

  await fs.writeFile(
    path.join(p.projectPath, '.esyrc'),
    `
      {
        "prefixPath": "${customEsyPrefix}"
      }
    `
  );

  const prevEnv = process.env;
  process.env = Object.assign({}, process.env, {OCAMLRUNPARAM: 'b'});

  await p.esy('install', {noEsyPrefix: true});
  await p.esy('build', {noEsyPrefix: true});

  await expect(p.esy('dep.cmd', {noEsyPrefix: true})).resolves.toEqual({
    stdout: '__dep__\n',
    stderr: '',
  });

  await expect(p.esy('which dep.cmd', {noEsyPrefix: true})).resolves.toEqual({
    stdout: expect.stringMatching(customEsyPrefix),
    stderr: '',
  });

  process.env = prevEnv;
});
