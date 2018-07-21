// @flow

const path = require('path');
const fs = require('fs');

const {initFixture} = require('../test/helpers');

describe('Build - with linked dep _build',  () => {

  it('package "dep" should be visible in all envs', async () => {
    expect.assertions(4);

    const p = await initFixture(path.join(__dirname, './fixtures/with-linked-dep-_build'));
    await p.esy('build');

    const expecting = expect.stringMatching('dep');

    const dep = await p.esy('dep');
    expect(dep.stdout).toEqual(expecting);

    const b = await p.esy('b dep');
    expect(b.stdout).toEqual(expecting);

    const x = await p.esy('x dep');
    expect(x.stdout).toEqual(expecting);


    const {stdout} = await p.esy('x with-linked-dep-_build');
    expect(stdout).toEqual(expect.stringMatching('with-linked-dep-_build'));
  });
});
