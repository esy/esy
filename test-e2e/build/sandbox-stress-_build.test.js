// @flow

const path = require('path');
const {initFixture, skipSuiteOnWindows} = require('../test/helpers');

skipSuiteOnWindows("#272");

it('Build - sandbox stress _build', async () => {
  expect.assertions(1);
  const p = await initFixture(path.join(__dirname, './fixtures/sandbox-stress-_build'));
  await p.esy('build');

  const {stdout} = await p.esy('x echo ok');
  expect(stdout).toEqual(expect.stringMatching('ok'));
});
