const childProcess = require('child_process');
const path = require('path');
const {promisify} = require('util');

const {initFixture} = require('../test/helpers');

const ESYCOMMAND = require.resolve('../../bin/esy');

const promiseExec = promisify(childProcess.exec);

it('Build - has build time deps', done => {
  expect.assertions(4);
  return initFixture('./build/fixtures/has-build-time-deps')
    .then(TEST_PATH => {
      return promiseExec(`${ESYCOMMAND} build`, {
        cwd: path.join(TEST_PATH, 'project'),
      }).then(() => TEST_PATH);
    })
    .then(TEST_PATH => {
      return promiseExec(`${ESYCOMMAND} x dep`, {cwd: path.join(TEST_PATH, 'project')})
        .then(({stdout}) =>
          expect(stdout).toEqual(
            expect.stringMatching(`dep was built with:
build-time-dep@2.0.0`),
          ),
        )
        .then(() =>
          promiseExec(`${ESYCOMMAND} x has-build-time-deps`, {
            cwd: path.join(TEST_PATH, 'project'),
          }),
        )
        .then(({stdout}) => {
          expect(stdout).toEqual(
            expect.stringMatching(`has-build-time-deps was built with:`),
          );
          expect(stdout).toEqual(expect.stringMatching(`build-time-dep@1.0.0`));
        })
        .then(() =>
          promiseExec(`${ESYCOMMAND} b build-time-dep`, {
            cwd: path.join(TEST_PATH, 'project'),
          }),
        )
        .then(({stdout}) =>
          expect(stdout).toEqual(expect.stringMatching(`build-time-dep@1.0.0`)),
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
