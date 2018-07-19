const path = require('path');
const fs = require('fs-extra');

const ESYCOMMAND = require.resolve('../../bin/esy');

function initFixture(fixture) {
  return fs.mkdtemp('/tmp/esy.XXXX').then(TEST_ROOT => {
    const TEST_PROJECT = path.join(TEST_ROOT, 'project');
    const TEST_BIN = path.join(TEST_ROOT, 'bin');

    return fs
      .mkdir(TEST_BIN)
      .then(() => fs.link(ESYCOMMAND, path.join(TEST_BIN, 'esy')))
      .then(() => fs.copy(fixture, TEST_PROJECT))
      .then(() => TEST_ROOT);
  });
}

module.exports = {
  initFixture,
};
