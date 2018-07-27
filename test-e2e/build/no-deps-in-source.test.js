// @flow

const path = require('path');
const {initFixture} = require('../test/helpers');

it('Build - no deps in source', async () => {
  expect.assertions(1);
  const p = await initFixture(path.join(__dirname, './fixtures/no-deps-in-source'));
  await p.esy('install');
  await p.esy('build');
  const {stdout} = await p.esy('x no-deps-in-source');
  expect(stdout).toEqual('no-deps-in-source\n');
});
