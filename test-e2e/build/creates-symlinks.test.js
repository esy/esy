const path = require('path');

const {initFixture, esyCommands} = require('../test/helpers');

it('Build - creats symlinks', async done => {
  expect.assertions(4);
  const TEST_PATH = await initFixture('./build/fixtures/creates-symlinks');
  const PROJECT_PATH = path.resolve(TEST_PATH, 'project');

  esyCommands.build(path.resolve(TEST_PATH, 'project'));

  const dep = await esyCommands.command(PROJECT_PATH, 'dep');
  const bDep = await esyCommands.b(PROJECT_PATH, 'dep');
  const xDep = await esyCommands.x(PROJECT_PATH, 'dep');

  const expecting = expect.stringMatching('dep');

  expect(dep.stdout).toEqual(expecting);
  expect(bDep.stdout).toEqual(expecting);
  expect(xDep.stdout).toEqual(expecting);

  let x = await esyCommands.x(PROJECT_PATH, 'creates-symlinks');
  expect(x.stdout).toEqual(expect.stringMatching('creates-symlinks'));

  done();
});
