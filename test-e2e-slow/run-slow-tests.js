// @flow

const {execSync} = require('child_process');
const os = require('os');

const isTaggedCommit = () => {
  const TRAVIS_TAG = process.env['TRAVIS_TAG'];
  const APPVEYOR_REPO_TAG = process.env['APPVEYOR_REPO_TAG'];
  return (
    (TRAVIS_TAG != null && TRAVIS_TAG !== '') ||
    (APPVEYOR_REPO_TAG != null && APPVEYOR_REPO_TAG === 'true')
  );
};

const getCommitMessage = () => {
  const TRAVIS_COMMIT_MESSAGE = process.env['TRAVIS_COMMIT_MESSAGE'];
  const APPVEYOR_REPO_COMMIT_MESSAGE = process.env['APPVEYOR_REPO_COMMIT_MESSAGE'];

  if (TRAVIS_COMMIT_MESSAGE) {
    return TRAVIS_COMMIT_MESSAGE;
  } else if (APPVEYOR_REPO_COMMIT_MESSAGE) {
    return APPVEYOR_REPO_COMMIT_MESSAGE;
  } else {
    return execSync('git log -n1').toString('utf8');
  }
};

const latestCommit = getCommitMessage();

const shouldRunSlowtests =
  isTaggedCommit() ||
  latestCommit.indexOf('@slowtest') !== -1 ||
  process.env['ESY_SLOWTEST'] != null;

if (!shouldRunSlowtests) {
  console.warn('Not running slowtests - commit message was: ' + latestCommit);
  process.exit(0);
} else {
  console.log('Running slowtests!' + latestCommit);
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
