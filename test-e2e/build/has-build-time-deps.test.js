const childProcess = require('child_process');
const path = require('path');

const {initFixture, esyCommands} = require('../test/helpers');

describe('Build - has build time deps', async () => {
  let TEST_PATH;
  let PROJECT_PATH;

  beforeAll(async done => {
    TEST_PATH = await initFixture('./build/fixtures/has-build-time-deps');
    PROJECT_PATH = path.resolve(TEST_PATH, 'project');
    await esyCommands.build(PROJECT_PATH, TEST_PATH);
    done();
  });

  it('x dep', async done => {
    expect.assertions(1);

    const {stdout} = await esyCommands.x(PROJECT_PATH, 'dep');
    expect(stdout).toEqual(
      expect.stringMatching(`dep was built with:
build-time-dep@2.0.0`),
    );

    done();
  });

  it('x has-build-time-deps', async done => {
    expect.assertions(2);

    const {stdout} = await esyCommands.x(PROJECT_PATH, 'has-build-time-deps');
    expect(stdout).toEqual(expect.stringMatching(`has-build-time-deps was built with:`));
    expect(stdout).toEqual(expect.stringMatching(`build-time-dep@1.0.0`));

    done();
  });

  it('b build-time-dep', async done => {
    expect.assertions(1);

    const {stdout} = await esyCommands.b(PROJECT_PATH, 'build-time-dep');
    expect(stdout).toEqual(expect.stringMatching(`build-time-dep@1.0.0`));

    done();
  });
});
