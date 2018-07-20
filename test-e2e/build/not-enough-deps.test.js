const path = require('path');

const {initFixture, esyCommands} = require('../test/helpers');

it('Build - not enough deps', async done => {
  expect.assertions(2);
  const TEST_PATH = await initFixture('./build/fixtures/not-enough-deps');
  const PROJECT_PATH = path.resolve(TEST_PATH, 'project');

  await esyCommands.build(PROJECT_PATH, PROJECT_PATH).catch(e => {
    expect(e.stderr).toEqual(expect.stringMatching('processing package: with-dep@1.0.0'));
    expect(e.stderr).toEqual(
      expect.stringMatching('invalid dependency dep: unable to resolve package'),
    );

    done();
  });
});
