// @flow

const path = require('path');
const {initFixture} = require('../test/helpers');

it('Build - no deps', async () => {
  expect.assertions(1);

  const p = await initFixture(path.join(__dirname, './fixtures/no-deps'));
  await p.esy('build');
  const {stdout} = await p.esy('x no-deps');
  expect(stdout).toEqual(expect.stringMatching('no-deps'));
});
