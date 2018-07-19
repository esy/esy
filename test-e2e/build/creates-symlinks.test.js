const childProcess = require('child_process');
const path = require('path');
const {promisify} = require('util');

const {initFixture} = require('../test/helpers');

const ESYCOMMAND = require.resolve('../../bin/esy');

const promiseExec = promisify(childProcess.exec);

it('Build - creats symlinks', done => {
  expect.assertions(4);
  return initFixture('./build/fixtures/creates-symlinks')
    .then(TEST_PATH => {
      return promiseExec(`${ESYCOMMAND} build`, {
        cwd: path.join(TEST_PATH, 'project'),
      }).then(() => TEST_PATH);
    })
    .then(TEST_PATH => {
      const expecting = expect.stringMatching('dep');
      return promiseExec(`${ESYCOMMAND} dep`, {cwd: path.join(TEST_PATH, 'project')})
        .then(({stdout}) => expect(stdout).toEqual(expecting))
        .then(() =>
          promiseExec(`${ESYCOMMAND} b dep`, {cwd: path.join(TEST_PATH, 'project')}),
        )
        .then(({stdout}) => expect(stdout).toEqual(expecting))
        .then(() =>
          promiseExec(`${ESYCOMMAND} x dep`, {cwd: path.join(TEST_PATH, 'project')}),
        )
        .then(({stdout}) => expect(stdout).toEqual(expecting))
        .then(() =>
          promiseExec(`${ESYCOMMAND} x creates-symlinks`, {
            cwd: path.join(TEST_PATH, 'project'),
          }),
        )
        .then(({stdout}) => {
          const match = expect.stringMatching('creates-symlinks');
          expect(stdout).toEqual(match);
        })
        .then(done);
    })
    .catch(e => {
      console.error(e);
      done();
    });
});
