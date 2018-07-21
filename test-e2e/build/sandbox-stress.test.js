// @flow

const path = require('path');
const {initFixture} = require('../test/helpers');

it('Build - sandbox stress', async () => {
  expect.assertions(1);
  const p = await initFixture(path.join(__dirname, './fixtures/sandbox-stress'));
  await p.esy('build');
  const {stdout} = await p.esy('x echo ok');
  expect(stdout).toEqual(expect.stringMatching('ok'));
});
