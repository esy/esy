const path = require('path');

const {initFixture, esyCommands} = require('../test/helpers');

it('Build - sandbox stress in source', async done => {
  expect.assertions(1);
  const TEST_PATH = await initFixture('./build/fixtures/sandbox-stress-in-source');
  const PROJECT_PATH = path.resolve(TEST_PATH, 'project');

  await esyCommands.build(PROJECT_PATH);

  const {stdout} = await esyCommands.x(PROJECT_PATH, 'echo ok');

  expect(stdout).toEqual(expect.stringMatching('ok'));

  done();
});
