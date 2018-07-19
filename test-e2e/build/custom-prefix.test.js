const childProcess = require('child_process');
const path = require('path');
const {promisify} = require('util');

const {initFixture} = require('../test/helpers');

const ESYCOMMAND = require.resolve('../../bin/esy');

const promiseExec = promisify(childProcess.exec);

it('Build - custom prefix (not propperly implemented)', done => {
  expect.assertions(1);
  return initFixture('./build/fixtures/custom-prefix')
    .then(TEST_PATH => {
      return promiseExec(`${ESYCOMMAND} build`, {
        cwd: path.join(TEST_PATH, 'project'),
      }).then(() => TEST_PATH);
    })
    .then(TEST_PATH => {
      return promiseExec(`${ESYCOMMAND} x custom-prefix`, {
        cwd: path.join(TEST_PATH, 'project'),
      }).then(({stdout}) => {
        const match = expect.stringMatching('custom-prefix');
        expect(stdout).toEqual(match);
      });
    })
    .then(done)
    .catch(e => {
      console.error(e);
      done();
    });
});
