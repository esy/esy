// @flow

const path = require('path');
const {initFixture} = require('../test/helpers');

it('Build - no deps backslash', async () => {
  expect.assertions(1);
  const p = await initFixture(path.join(__dirname, './fixtures/no-deps-backslash'));
  await p.esy('build');

  const {stdout} = await p.esy('x no-deps-backslash');
  expect(stdout).toEqual(expect.stringMatching(/\\ no-deps-backslash \\/));
});
