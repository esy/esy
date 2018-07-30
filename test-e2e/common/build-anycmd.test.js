// @flow

const path = require('path');

const {genFixture} = require('../test/helpers');
const fixture = require('./fixture.js');

it('Common - build anycmd', async () => {
  const p = await genFixture(...fixture.simpleProject);

  await p.esy('build');

  await expect(p.esy('build dep')).resolves.toEqual({
    stdout: '__dep__\n',
    stderr: '',
  });

  await expect(p.esy('b dep')).resolves.toEqual({
    stdout: '__dep__\n',
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
