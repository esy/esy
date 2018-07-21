// @flow

const path = require('path');
const fs = require('fs');

const {initFixture} = require('../test/helpers');

describe('Build - with linked dep _build', () => {
  let p;

  beforeAll(async () => {
    p = await initFixture(path.join(__dirname, './fixtures/with-linked-dep-sandbox-env'));
    await p.esy('build');
  });

  it("sandbox env should be visible in runtime dep's all envs", async () => {
    expect.assertions(3);

    const expecting = expect.stringMatching('global-sandbox-env-var-in-dep');

    const dep = await p.esy('dep');
    expect(dep.stdout).toEqual(expecting);

    const b = await p.esy('b dep');
    expect(b.stdout).toEqual(expecting);

    const x = await p.esy('x dep');
    expect(x.stdout).toEqual(expecting);
  });

  it("sandbox env should not be available in build time dep's envs", async () => {
    expect.assertions(2);

    const expecting = expect.stringMatching('-in-dep2');

    const dep = await p.esy('dep2');
    expect(dep.stdout).toEqual(expecting);

    const b = await p.esy('b dep2');
    expect(b.stdout).toEqual(expecting);
  });

  it("sandbox env should not be available in dev dep's envs", async () => {
    expect.assertions(2);

    const dep = await p.esy('dep3');
    expect(dep.stdout).toEqual(expect.stringMatching('-in-dep3'));

    const {stdout} = await p.esy('x with-linked-dep-sandbox-env');
    expect(stdout).toEqual(expect.stringMatching('with-linked-dep-sandbox-env'));

  });
});
