const childProcess = require('child_process');
const path = require('path');
const {promisify} = require('util');

const {initFixture} = require('../test/helpers');

const ESYCOMMAND = require.resolve('../../bin/esy');

const promiseExec = promisify(childProcess.exec);

it('Build - augment path', done => {
  expect.assertions(3);
  return initFixture('./build/fixtures/augment-path')
    .then(TEST_PATH => {
      return promiseExec(`${ESYCOMMAND} build`, {
        cwd: path.join(TEST_PATH, 'project'),
      }).then(() => TEST_PATH);
    })
    .then(TEST_PATH => {
      const expecting = expect.stringMatching('dep');
      return promiseExec(`${ESYCOMMAND} dep`, {cwd: path.join(TEST_PATH, 'project')})
        .then(dep => expect(dep.stdout).toEqual(expecting))
        .then(() =>
          promiseExec(`${ESYCOMMAND} b dep`, {cwd: path.join(TEST_PATH, 'project')}),
        )
        .then(b => expect(b.stdout).toEqual(expecting))
        .then(() =>
          promiseExec(`${ESYCOMMAND} x dep`, {cwd: path.join(TEST_PATH, 'project')}),
        )
        .then(x => expect(x.stdout).toEqual(expecting))
        .then(done);
    })
    .catch(e => {
      console.error(e);
      done();
    });
});
