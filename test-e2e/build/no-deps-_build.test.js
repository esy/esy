const path = require('path');

const {initFixture, esyCommands} = require('../test/helpers');

it('Build - no deps _build', async done => {
  expect.assertions(1);
  const TEST_PATH = await initFixture('./build/fixtures/no-deps-_build');
  const PROJECT_PATH = path.resolve(TEST_PATH, 'project');

  await esyCommands.build(PROJECT_PATH);

  const {stdout} = await esyCommands.x(PROJECT_PATH, 'no-deps-_build');

  expect(stdout).toEqual(expect.stringMatching(`no-deps-_build`));

  done();
});
