// @flow

const path = require('path');

const {initFixture} = require('../test/helpers');

it('Build - creates symlinks', async () => {
  expect.assertions(4);
  const p = await initFixture(path.join(__dirname, './fixtures/creates-symlinks'));

  await p.esy('build');

  const expecting = expect.stringMatching('dep');

  const dep = await p.esy('dep');
  expect(dep.stdout).toEqual(expecting);
  const bDep = await p.esy('b dep');
  expect(bDep.stdout).toEqual(expecting);
  const xDep = await p.esy('x dep');
  expect(xDep.stdout).toEqual(expecting);

  let x = await p.esy('x creates-symlinks');
  expect(x.stdout).toEqual(expect.stringMatching('creates-symlinks'));
});
