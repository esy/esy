// @flow

const path = require('path');
const {initFixture} = require('../test/helpers');

describe('Build - with dep', () => {
  it('package "dep" should be visible in all envs', async () => {
    expect.assertions(4);

    const p = await initFixture(path.join(__dirname, './fixtures/with-dep'));
    await p.esy('build');

    const expecting = expect.stringMatching('dep');

    const dep = await p.esy('dep');
    expect(dep.stdout).toEqual(expecting);

    const b = await p.esy('b dep');
    expect(b.stdout).toEqual(expecting);

    const x = await p.esy('x dep');
    expect(x.stdout).toEqual(expecting);

    const {stdout} = await p.esy('x with-dep');
    expect(stdout).toEqual(expect.stringMatching('with-dep'));
  });
});
