const path = require('path');
const fs = require('fs');
const {promisify} = require('util');

const open = promisify(fs.open);
const close = promisify(fs.close);

const {initFixture, esyCommands} = require('../test/helpers');

it('Build - with linked dep _build', async done => {
  expect.assertions(7);
  const TEST_PATH = await initFixture('./build/fixtures/with-linked-dep-sandbox-env');
  const PROJECT_PATH = path.resolve(TEST_PATH, 'project');

  await esyCommands.build(PROJECT_PATH, TEST_PATH);

  const dep = await esyCommands.command(PROJECT_PATH, 'dep');
  const b = await esyCommands.b(PROJECT_PATH, 'dep');
  const x = await esyCommands.x(PROJECT_PATH, 'dep');

  const expecting = expect.stringMatching('global-sandbox-env-var-in-dep');
  expect(x.stdout).toEqual(expecting);
  expect(b.stdout).toEqual(expecting);
  expect(dep.stdout).toEqual(expecting);

  const dep2 = await esyCommands.command(PROJECT_PATH, 'dep2');
  const b2 = await esyCommands.b(PROJECT_PATH, 'dep2');

  const expecting2 = expect.stringMatching('-in-dep2');
  expect(dep2.stdout).toEqual(expecting2);
  expect(b2.stdout).toEqual(expecting2);

  const dep3 = await esyCommands.command(PROJECT_PATH, 'dep3');
  expect(dep3.stdout).toEqual(expect.stringMatching('-in-dep3'));

  const {stdout} = await esyCommands.x(PROJECT_PATH, 'with-linked-dep-sandbox-env');
  expect(stdout).toEqual(expect.stringMatching('with-linked-dep-sandbox-env'));

  done();
});
