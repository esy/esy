// @flow

const path = require('path');
const {initFixture} = require('../test/helpers');

describe('Build - not enough deps', () => {
  it("should fail as there's not enough deps and output relevant info", async () => {
    expect.assertions(2);
    const p = await initFixture(path.join(__dirname, './fixtures/not-enough-deps'));

    await p.esy('build').catch(e => {
      expect(e.stderr).toEqual(
        expect.stringMatching('processing package: with-dep@1.0.0'),
      );
      expect(e.stderr).toEqual(
        expect.stringMatching('invalid dependency dep: unable to resolve package'),
      );
    });
  });
});
