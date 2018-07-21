const path = require('path');

const {initFixture, esyCommands} = require('../test/helpers');

describe('Build - not enough deps', async () => {
  let TEST_PATH;
  let PROJECT_PATH;

  beforeAll(async done => {
    TEST_PATH = await initFixture('./build/fixtures/not-enough-deps');
    PROJECT_PATH = path.resolve(TEST_PATH, 'project');

    done();
  });

  it("should fail as there's not enough deps and output relevant info", async done => {
    expect.assertions(2);

    await esyCommands.build(PROJECT_PATH, PROJECT_PATH).catch(e => {
      expect(e.stderr).toEqual(
        expect.stringMatching('processing package: with-dep@1.0.0'),
      );
      expect(e.stderr).toEqual(
        expect.stringMatching('invalid dependency dep: unable to resolve package'),
      );
    });

    done();
  });
});
