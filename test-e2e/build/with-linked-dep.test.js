const path = require('path');
const fs = require('fs');
const {promisify} = require('util');

const open = promisify(fs.open);
const close = promisify(fs.close);

const {initFixture, esyCommands} = require('../test/helpers');

it('Build - with linked dep', async done => {
  expect.assertions(6);
  const TEST_PATH = await initFixture('./build/fixtures/with-linked-dep');
  const PROJECT_PATH = path.resolve(TEST_PATH, 'project');

  await esyCommands.build(PROJECT_PATH, TEST_PATH);

  const dep = await esyCommands.command(PROJECT_PATH, 'dep');
  const b = await esyCommands.b(PROJECT_PATH, 'dep');
  const x = await esyCommands.x(PROJECT_PATH, 'dep');

  const expecting = expect.stringMatching('dep');

  expect(x.stdout).toEqual(expecting);
  expect(b.stdout).toEqual(expecting);
  expect(dep.stdout).toEqual(expecting);

  const {stdout} = await esyCommands.x(PROJECT_PATH, 'with-linked-dep');
  expect(stdout).toEqual(expect.stringMatching('with-linked-dep'));

  const noOpBuild = await esyCommands.build(PROJECT_PATH, TEST_PATH);
  expect(noOpBuild.stdout).not.toEqual(
    expect.stringMatching('Building dep@1.0.0: starting'),
  );

  await open(path.join(PROJECT_PATH, 'dep', 'dummy'), 'w').then(close);

  const rebuild = await esyCommands.build(PROJECT_PATH, TEST_PATH);
  // TODO: why is this on stderr?
  expect(rebuild.stderr).toEqual(expect.stringMatching('Building dep@1.0.0: starting'));

  done();
});
