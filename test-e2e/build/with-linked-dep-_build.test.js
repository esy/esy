const path = require('path');
const fs = require('fs');
const {promisify} = require('util');

const {initFixture, esyCommands} = require('../test/helpers');

describe('Build - with linked dep _build', async () => {
  let TEST_PATH;
  let PROJECT_PATH;

  beforeAll(async done => {
    TEST_PATH = await initFixture('./build/fixtures/with-linked-dep-_build');
    PROJECT_PATH = path.resolve(TEST_PATH, 'project');

    await esyCommands.build(PROJECT_PATH, TEST_PATH);
    done();
  });

  it('package "dep" should be visible in all envs', async done => {
    expect.assertions(4);
    const dep = await esyCommands.command(PROJECT_PATH, 'dep');
    const b = await esyCommands.b(PROJECT_PATH, 'dep');
    const x = await esyCommands.x(PROJECT_PATH, 'dep');

    const expecting = expect.stringMatching('dep');

    expect(x.stdout).toEqual(expecting);
    expect(b.stdout).toEqual(expecting);
    expect(dep.stdout).toEqual(expecting);

    const {stdout} = await esyCommands.x(PROJECT_PATH, 'with-linked-dep-_build');
    expect(stdout).toEqual(expect.stringMatching('with-linked-dep-_build'));

    done();
  });
});
