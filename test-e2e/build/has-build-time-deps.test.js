// @flow

const childProcess = require('child_process');
const path = require('path');

const {initFixture} = require('../test/helpers');

describe('Build - has build time deps', () => {

  let p;

  beforeAll(async () => {
    p = await initFixture(path.join(__dirname, './fixtures/has-build-time-deps'));
    await p.esy('build');
  });

  it('x dep', async () => {
    expect.assertions(1);

    const {stdout} = await p.esy('dep');
    expect(stdout).toEqual(
      expect.stringMatching(`dep was built with:
build-time-dep@2.0.0`),
    );

  });

  it('x has-build-time-deps', async () => {
    expect.assertions(2);

    const {stdout} = await p.esy('x has-build-time-deps');
    expect(stdout).toEqual(expect.stringMatching(`has-build-time-deps was built with:`));
    expect(stdout).toEqual(expect.stringMatching(`build-time-dep@1.0.0`));
  });

  it('b build-time-dep', async () => {
    expect.assertions(1);

    const {stdout} = await p.esy('b build-time-dep');
    expect(stdout).toEqual(expect.stringMatching(`build-time-dep@1.0.0`));
  });
});
