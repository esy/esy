// @flow
const path = require('path');

const {initFixture} = require('../test/helpers');

it('Build - errorneous build', async () => {
  const p = await initFixture(path.join(__dirname, './fixtures/errorneous-build'));
  try {
    await p.esy('build')
  } catch(err) {
    expect(String(err)).toEqual(
      expect.stringMatching('command failed'),
    );
    return;
  }
  expect(true).toBeFalsy();
});
