const path = require('path');
const fs = require('fs');
const {promisify} = require('util');

const {initFixture, esyCommands} = require('../test/helpers');

describe('Build - with linked dep _build', async () => {
  let TEST_PATH;
  let PROJECT_PATH;

  beforeAll(async done => {
    TEST_PATH = await initFixture('./build/fixtures/with-linked-dep-sandbox-env');
    PROJECT_PATH = path.resolve(TEST_PATH, 'project');

    await esyCommands.build(PROJECT_PATH, TEST_PATH);
    done();
  });

  it("sandbox env should be visible in runtime dep's all envs", async done => {
    expect.assertions(3);
    const dep = await esyCommands.command(PROJECT_PATH, 'dep');
    const b = await esyCommands.b(PROJECT_PATH, 'dep');
    const x = await esyCommands.x(PROJECT_PATH, 'dep');

    const expecting = expect.stringMatching('global-sandbox-env-var-in-dep');
    expect(x.stdout).toEqual(expecting);
    expect(b.stdout).toEqual(expecting);
    expect(dep.stdout).toEqual(expecting);

    done();
  });

  it("sandbox env should not be available in build time dep's envs", async done => {
    expect.assertions(2);
    const dep = await esyCommands.command(PROJECT_PATH, 'dep2');
    const b = await esyCommands.b(PROJECT_PATH, 'dep2');

    const expecting = expect.stringMatching('-in-dep2');
    expect(dep.stdout).toEqual(expecting);
    expect(b.stdout).toEqual(expecting);

    done();
  });

  it("sandbox env should not be available in dev dep's envs", async done => {
    expect.assertions(2);
    const dep = await esyCommands.command(PROJECT_PATH, 'dep3');
    expect(dep.stdout).toEqual(expect.stringMatching('-in-dep3'));

    const {stdout} = await esyCommands.x(PROJECT_PATH, 'with-linked-dep-sandbox-env');
    expect(stdout).toEqual(expect.stringMatching('with-linked-dep-sandbox-env'));

    done();
  });
});
