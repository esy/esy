// @flow

const path = require('path');

const {initFixture} = require('../test/helpers');

it('Build - no deps _build', async () => {
  expect.assertions(1);
  const p = await initFixture(path.join(__dirname, './fixtures/no-deps-_build'));
  await p.esy('install');
  await p.esy('build');
  const {stdout} = await p.esy('x no-deps-_build');
  expect(stdout).toEqual('no-deps-_build\n');
});
