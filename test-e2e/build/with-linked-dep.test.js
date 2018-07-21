// @flow

const path = require('path');
const fs = require('fs');
const {promisify} = require('util');
const open = promisify(fs.open);
const close = promisify(fs.close);

const {initFixture} = require('../test/helpers');

describe('Build - with linked dep', () => {
  let p;

  beforeAll(async () => {
    p = await initFixture(path.join(__dirname, './fixtures/with-linked-dep'));
    await p.esy('build');
  });

  it('package "dep" should be visible in all envs', async () => {
    expect.assertions(4);

    const dep = await p.esy('dep');
    const b = await p.esy('b dep');
    const x = await p.esy('x dep');

    const expecting = expect.stringMatching('dep');

    expect(x.stdout).toEqual(expecting);
    expect(b.stdout).toEqual(expecting);
    expect(dep.stdout).toEqual(expecting);

    const {stdout} = await p.esy('x with-linked-dep');
    expect(stdout).toEqual(expect.stringMatching('with-linked-dep'));
  });

  it('should not rebuild dep with no changes', async done => {
    expect.assertions(1);

    const noOpBuild = await p.esy('build');
    expect(noOpBuild.stdout).not.toEqual(
      expect.stringMatching('Building dep@1.0.0: starting'),
    );

    done();
  });

  it('should rebuild if file has been added', async () => {
    expect.assertions(1);

    await open(path.join(p.projectPath, 'dep', 'dummy'), 'w').then(close);

    const rebuild = await p.esy('build');
    // TODO: why is this on stderr?
    expect(rebuild.stderr).toEqual(expect.stringMatching('Building dep@1.0.0: starting'));
  });
});
