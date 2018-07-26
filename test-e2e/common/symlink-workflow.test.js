// @flow

const path = require('path');
const fs = require('fs-extra');

const {initFixture, promiseExec, ESYCOMMAND, skipSuiteOnWindows} = require('../test/helpers');

skipSuiteOnWindows("Needs investigation.")

describe('Common - symlink workflow', async () => {
  let p;
  let appEsy;

  beforeAll(async () => {
    p = await initFixture(path.join(__dirname, 'fixtures', 'symlink-workflow'));
    appEsy = args =>
      promiseExec(`${ESYCOMMAND} ${args}`, {
        cwd: path.resolve(p.projectPath, 'app'),
        env: {...process.env, ESY__PREFIX: p.esyPrefixPath},
      });
  });

  it('works without changes', async () => {
    expect.assertions(2);

    await appEsy('install');
    await appEsy('build');

    const dep = await appEsy('dep');
    expect(dep.stdout).toEqual(expect.stringMatching('HELLO'));
    const anotherDep = await appEsy('another-dep');
    expect(anotherDep.stdout).toEqual(expect.stringMatching('HELLO'));
  });

  it('works with modified dep sources', async () => {
    expect.assertions(1);

    await fs.writeFile(
      path.join(p.projectPath, 'dep', 'dep'),
      '#!/bin/bash\necho HELLO_MODIFIED\n',
    );

    await appEsy('build');
    const dep = await appEsy('dep');
    expect(dep.stdout).toEqual(expect.stringMatching('HELLO_MODIFIED'));
  });
});
