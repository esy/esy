// @flow

const path = require('path');
const {initFixture} = require('../test/helpers');

describe('Build - with dev dep', () => {

  let p;

  beforeAll(async () => {
    p = await initFixture(path.join(__dirname, './fixtures/with-dev-dep'));
    await p.esy('build');
  });

  it('package "dep" should be visible in all envs', async () => {
    expect.assertions(3);

    const expecting = expect.stringMatching('dep');

    const dep = await p.esy('dep');
    expect(dep.stdout).toEqual(expecting);

    const bDep = await p.esy('b dep');
    expect(bDep.stdout).toEqual(expecting);

    const xDep = await p.esy('x dep');
    expect(xDep.stdout).toEqual(expecting);
  });

  it('package "dev-dep" should be visible only in command env', async () => {
    expect.assertions(4);

    const expecting = expect.stringMatching('dev-dep');

    const dep = await p.esy('dev-dep');
    expect(dep.stdout).toEqual(expecting);

    const xDep = await p.esy('x dev-dep');
    expect(xDep.stdout).toEqual(expecting);

    const {stdout} = await p.esy('x with-dev-dep');
    expect(stdout).toEqual(expect.stringMatching('with-dev-dep'));

    return expect(p.esy('b dev-dep')).rejects.toThrow();
  });
});
