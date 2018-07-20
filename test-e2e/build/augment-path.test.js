const path = require('path');

const {initFixture, esyCommands} = require('../test/helpers');

it('Build - augment path', async done => {
  expect.assertions(3);
  const TEST_PATH = await initFixture('./build/fixtures/augment-path');

  await esyCommands.build(path.resolve(TEST_PATH, 'project'));

  const dep = await esyCommands.command(path.join(TEST_PATH, 'project'), 'dep');
  const b = await esyCommands.b(path.join(TEST_PATH, 'project'), 'dep');
  const x = await esyCommands.x(path.join(TEST_PATH, 'project'), 'dep');

  const expecting = expect.stringMatching('dep');

  expect(x.stdout).toEqual(expecting);
  expect(b.stdout).toEqual(expecting);
  expect(dep.stdout).toEqual(expecting);

  done();
});
