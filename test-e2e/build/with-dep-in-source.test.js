const path = require('path');

const {initFixture, esyCommands} = require('../test/helpers');

it('Build - with dep in source', async done => {
  expect.assertions(4);
  const TEST_PATH = await initFixture('./build/fixtures/with-dep-in-source');
  const PROJECT_PATH = path.resolve(TEST_PATH, 'project');

  await esyCommands.build(PROJECT_PATH, TEST_PATH);

  const dep = await esyCommands.command(PROJECT_PATH, 'dep');
  const b = await esyCommands.b(PROJECT_PATH, 'dep');
  const x = await esyCommands.x(PROJECT_PATH, 'dep');

  const expecting = expect.stringMatching('dep');

  expect(x.stdout).toEqual(expecting);
  expect(b.stdout).toEqual(expecting);
  expect(dep.stdout).toEqual(expecting);

  const {stdout} = await esyCommands.x(PROJECT_PATH, 'with-dep-in-source');
  expect(stdout).toEqual(expect.stringMatching('with-dep-in-source'));

  done();
});
