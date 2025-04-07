// @flow

const path = require('path');
const {createTestSandbox, packageJson} = require('../test/helpers');

const fixture = [
  packageJson({
    name: 'not-enough-deps',
    version: '1.0.0',
    license: 'MIT',
    esy: {
      build: 'true',
    },
    dependencies: {
      dep: '*',
    },
  }),
];

describe('Build - not enough deps', () => {
  it("should fail as there's not enough deps and output relevant info", async () => {
    const p = await createTestSandbox(...fixture);

    await p.esy('build').catch(e => {
      expect(e.stderr).toEqual(
        expect.stringMatching('error Project is missing lock files. Run `esy install`'),
      );
    });
  });
});
