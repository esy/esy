// @flow

const os = require('os');
const path = require('path');
const del = require('del');
const fs = require('fs-extra');

const {genFixture, skipSuiteOnWindows} = require('../test/helpers');
const fixture = require('./fixture.js');

skipSuiteOnWindows();

it('Common - esy prefix via esyrc', async () => {

  const tmp = process.platform === 'win32' ? os.tmpdir() : '/tmp';
  const tmpPath = await fs.mkdtemp(path.join(tmp, 'XXXX'));
  const customEsyPrefix = path.join(tmpPath, 'prefix');

  const p = await genFixture(...fixture.simpleProject);

  await fs.writeFile(
    path.join(p.projectPath, '.esyrc'),
    `esy-prefix-path: ${customEsyPrefix}`,
  );

  const prevEnv = process.env;
  process.env = Object.assign({}, process.env, {OCAMLRUNPARAM: 'b'});

  await p.esy('build', {noEsyPrefix: true});

  await expect(p.esy('dep', {noEsyPrefix: true})).resolves.toEqual({
    stdout: '__dep__\n',
    stderr: '',
  });

  await expect(p.esy('which dep', {noEsyPrefix: true})).resolves.toEqual({
    stdout: expect.stringMatching(customEsyPrefix),
    stderr: '',
  });

  process.env = prevEnv;
});
