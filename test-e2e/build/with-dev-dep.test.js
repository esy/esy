const path = require('path');

const {initFixture, esyCommands} = require('../test/helpers');

describe('Build - with dev dep', () => {
  let TEST_PATH;
  let PROJECT_PATH;

  beforeAll(async done => {
    TEST_PATH = await initFixture('./build/fixtures/with-dev-dep');
    PROJECT_PATH = path.resolve(TEST_PATH, 'project');

    await esyCommands.build(PROJECT_PATH, TEST_PATH);
    done();
  });

  it('package "dep" should be visible in all envs', async done => {
    expect.assertions(3);

    const dep = await esyCommands.command(PROJECT_PATH, 'dep');
    const bDep = await esyCommands.b(PROJECT_PATH, 'dep');
    const xDep = await esyCommands.x(PROJECT_PATH, 'dep');

    const expecting = expect.stringMatching('dep');

    expect(dep.stdout).toEqual(expecting);
    expect(bDep.stdout).toEqual(expecting);
    expect(xDep.stdout).toEqual(expecting);

    done();
  });

  it('package "dev-dep" should be visible only in command env', async () => {
    expect.assertions(4);

    const dep = await esyCommands.command(PROJECT_PATH, 'dev-dep');
    const xDep = await esyCommands.x(PROJECT_PATH, 'dev-dep');

    const expecting = expect.stringMatching('dev-dep');

    expect(dep.stdout).toEqual(expecting);
    expect(xDep.stdout).toEqual(expecting);

    const {stdout} = await esyCommands.x(PROJECT_PATH, 'with-dev-dep');
    expect(stdout).toEqual(expect.stringMatching('with-dev-dep'));

    return expect(esyCommands.b(PROJECT_PATH, 'dev-dep')).rejects.toThrow();
  });
});
