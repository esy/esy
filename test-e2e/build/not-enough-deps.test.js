// @flow

const path = require('path');
const {genFixture, packageJson} = require('../test/helpers');

const fixture = [
  packageJson({
    "name": "not-enough-deps",
    "version": "1.0.0",
    "license": "MIT",
    "esy": {
      "build": "true"
    },
    "dependencies": {
      "dep": "*"
    }
  })
];

describe('Build - not enough deps', () => {
  it("should fail as there's not enough deps and output relevant info", async () => {
    const p = await genFixture(...fixture);

    await p.esy('build').catch(e => {
      expect(e.stderr).toEqual(
        expect.stringMatching('processing package: not-enough-deps@1.0.0'),
      );
      expect(e.stderr).toEqual(
        expect.stringMatching('invalid dependency dep: unable to resolve package'),
      );
    });
  });
});
