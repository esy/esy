// @flow

const path = require('path');

const {initFixture} = require('../test/helpers');

it('Build - no deps _build', async () => {
  expect.assertions(1);
  const p = await initFixture(path.join(__dirname, './fixtures/no-deps-_build'));
  await p.esy('build');
  const {stdout} = await p.esy('x no-deps-_build');
  expect(stdout).toEqual(expect.stringMatching('no-deps-_build'));
});
