// @flow

const {execSync} = require('child_process');
const os = require('os');

const getCommitMessage = () => {
  let travisCommit = process.env['TRAVIS_COMMIT_MESSAGE'];
  let appVeyorCommit = process.env['APPVEYOR_REPO_COMMIT_MESSAGE'];

  if (travisCommit) {
    return travisCommit;
  } else if (appVeyorCommit) {
    return appVeyorCommit;
  } else {
    return execSync('git log -n1').toString('utf8');
  }
};

const latestCommit = getCommitMessage();

if (latestCommit.indexOf('@slowtest') === -1 && !process.env['ESY_SLOWTEST']) {
  console.warn('Not running slowtests - commit message was: ' + latestCommit);
  process.exit(0);
}

const isWindows = os.platform() === 'win32';

console.log('Running test suite: e2e (slow tests)');

require('./build-top-100-opam.test.js');
require('./install-npm.test.js');
require('./esy.test.js');

if (!isWindows) {
  // Disabling below tests due to exceeding timeframe:

  // Reason test blocked by: https://github.com/facebook/reason/pull/2209
  // require("./reason.test.js");

  // Windows: Needs investigation
  // require("./repromise.test.js");

  // Windows: Fastpack build not supported yet.
  // require("./fastpack.test.js");

  // Windows: Release blocked by #418
  require('./release.test.js');
}
