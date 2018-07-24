// @flow

const path = require('path');

const {initFixture} = require('../test/helpers');

describe('Build - augment path', () => {
  it('package "dep" should be visible in all envs', async () => {
    expect.assertions(3);

    const p = await initFixture(path.join(__dirname, './fixtures/augment-path'));
    await p.esy('build');

    const expecting = expect.stringMatching('dep');

    const dep = await p.esy('dep');
    expect(dep.stdout).toEqual(expecting);

    const b = await p.esy('b dep');
    expect(b.stdout).toEqual(expecting);

    const x = await p.esy('x dep');
    expect(x.stdout).toEqual(expecting);
  });
});
