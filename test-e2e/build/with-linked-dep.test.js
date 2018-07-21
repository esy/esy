const path = require('path');
const fs = require('fs');
const {promisify} = require('util');

const open = promisify(fs.open);
const close = promisify(fs.close);

const {initFixture, esyCommands} = require('../test/helpers');

describe('Build - with linked dep', async () => {
  let TEST_PATH;
  let PROJECT_PATH;

  beforeAll(async done => {
    TEST_PATH = await initFixture('./build/fixtures/with-linked-dep');
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

    const {stdout} = await esyCommands.x(PROJECT_PATH, 'with-linked-dep');
    expect(stdout).toEqual(expect.stringMatching('with-linked-dep'));

    done();
  });

  it('should not rebuild dep with no changes', async done => {
    expect.assertions(1);

    const noOpBuild = await esyCommands.build(PROJECT_PATH, TEST_PATH);
    expect(noOpBuild.stdout).not.toEqual(
      expect.stringMatching('Building dep@1.0.0: starting'),
    );

    done();
  });

  it('should rebuild if file has been added', async done => {
    expect.assertions(1);

    await open(path.join(PROJECT_PATH, 'dep', 'dummy'), 'w').then(close);

    const rebuild = await esyCommands.build(PROJECT_PATH, TEST_PATH);
    // TODO: why is this on stderr?
    expect(rebuild.stderr).toEqual(expect.stringMatching('Building dep@1.0.0: starting'));

    done();
  });
});
