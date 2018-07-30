// @flow

const path = require('path');
const {genFixture, packageJson} = require('../test/helpers');

const fixture = [
  packageJson({
    "name": "not-enough-deps",
    "version": "1.0.0",
    "license": "MIT",
    "esy": {
      "build": [
        [
          "bash",
          "-c",
          "echo '#!/bin/bash\necho #{self.name}' > #{self.target_dir / self.name}"
        ],
        "chmod +x $cur__target_dir/$cur__name"
      ],
      "install": ["cp $cur__target_dir/$cur__name $cur__bin/$cur__name"]
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
