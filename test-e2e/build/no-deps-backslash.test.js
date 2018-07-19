const childProcess = require('child_process');
const path = require('path');
const {promisify} = require('util');

const {initFixture} = require('../test/helpers');

const ESYCOMMAND = require.resolve('../../bin/esy');

const promiseExec = promisify(childProcess.exec);

it('Build - has build time deps', done => {
  expect.assertions(1);
  return initFixture('./build/fixtures/no-deps-backslash')
    .then(TEST_PATH => {
      return promiseExec(`${ESYCOMMAND} build`, {
        cwd: path.join(TEST_PATH, 'project'),
      }).then(() => TEST_PATH);
    })
    .then(TEST_PATH => {
      return promiseExec(`${ESYCOMMAND} x no-deps-backslash`, {
        cwd: path.join(TEST_PATH, 'project'),
      })
        .then(({stdout}) =>
          expect(stdout).toEqual(expect.stringMatching(/\\ no-deps-backslash \\/)),
        )
        .then(done);
    })
    .then(done)
    .catch(e => {
      expect(e).toBeNull();
      console.error(e);
      done();
    });
});
