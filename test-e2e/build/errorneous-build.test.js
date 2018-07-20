const path = require('path');

const {initFixture, esyCommands} = require('../test/helpers');

it('Build - errorneous build', async done => {
  const TEST_PATH = await initFixture('./build/fixtures/errorneous-build');
  const PROJECT_PATH = path.resolve(TEST_PATH, 'project');

  expect(esyCommands.build(PROJECT_PATH)).rejects.toThrow();

  done();
});
