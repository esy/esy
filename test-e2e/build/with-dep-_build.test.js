// @flow

const path = require('path');
const {initFixture, skipSuiteOnWindows} = require('../test/helpers');

skipSuiteOnWindows("#272");

describe('Build - with dep _build', () => {

  let p;

  beforeEach(async () => {
    p = await initFixture(path.join(__dirname, './fixtures/with-dep-_build'));
    await p.esy('build');
  });

  it('package "dep" should be visible in all envs', async () => {
    expect.assertions(3);

    const expecting = expect.stringMatching('dep');

    const dep = await p.esy('dep');
    expect(dep.stdout).toEqual(expecting);
    const b = await p.esy('b dep');
    expect(b.stdout).toEqual(expecting);
    const x = await p.esy('x dep');
    expect(x.stdout).toEqual(expecting);
  });

  it('with-dep-_build', async () => {
    expect.assertions(1);

    const {stdout} = await p.esy('x with-dep-_build');
    expect(stdout).toEqual(expect.stringMatching('with-dep-_build'));
  });
});
