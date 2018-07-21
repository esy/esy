const path = require('path');

const {initFixture, esyCommands} = require('../test/helpers');

it('Build - custom prefix', async done => {
  expect.assertions(1);
  const TEST_PATH = await initFixture('./build/fixtures/custom-prefix');
  const PROJECT_PATH = path.resolve(TEST_PATH, 'project');

  // same as unset ESY__PREFIX
  await esyCommands.build(PROJECT_PATH, null);

  const {stdout} = await esyCommands.x(PROJECT_PATH, 'custom-prefix');

  expect(stdout).toEqual(expect.stringMatching('custom-prefix'));

  done();
});
