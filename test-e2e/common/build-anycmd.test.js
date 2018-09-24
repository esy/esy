// @flow

const os = require('os');
const path = require('path');

const {createTestSandbox, skipSuiteOnWindows} = require('../test/helpers');
const fixture = require('./fixture.js');

skipSuiteOnWindows();

it('Common - build anycmd', async () => {
  const p = await createTestSandbox();
  await p.fixture(...fixture.makeSimpleProject(p));

  await p.esy('build');

  await expect(p.esy('build dep.cmd')).resolves.toEqual({
    stdout: '__dep__' + os.EOL,
    stderr: '',
  });

  await expect(p.esy('b dep.cmd')).resolves.toEqual({
    stdout: '__dep__' + os.EOL,
    stderr: '',
  });

  // make sure exit code is preserved
  await expect(p.esy("b bash -c 'exit 1'")).rejects.toEqual(
    expect.objectContaining({code: 1}),
  );
  await expect(p.esy("b bash -c 'exit 7'")).rejects.toEqual(
    expect.objectContaining({code: 7}),
  );
});
