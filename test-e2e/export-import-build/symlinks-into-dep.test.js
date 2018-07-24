// @flow

const path = require('path');
const fs = require('fs-extra');
const tar = require('tar');
const del = require('del');

const {initFixture} = require('../test/helpers');

describe('export import build - import symlinks into dep', async () => {
  let p;

  beforeAll(async () => {
    p = await initFixture(path.join(__dirname, './fixtures/symlinks-into-dep'));
    await p.esy('build');
  });

  it('package "subdep" should be visible in all envs', async () => {
    expect.assertions(3);

    const expecting = expect.stringMatching('subdep');

    const subdep = await p.esy('subdep');
    expect(subdep.stdout).toEqual(expecting);
    const b = await p.esy('b subdep');
    expect(b.stdout).toEqual(expecting);
    const x = await p.esy('x subdep');
    expect(x.stdout).toEqual(expecting);
  });

  it('same for package "dep" but it should reuse the impl of "subdep"', async () => {
    expect.assertions(3);

    const expecting = expect.stringMatching('subdep');

    const subdep = await p.esy('dep');
    expect(subdep.stdout).toEqual(expecting);
    const b = await p.esy('b dep');
    expect(b.stdout).toEqual(expecting);
    const x = await p.esy('x dep');
    expect(x.stdout).toEqual(expecting);
  });

  it('and root package links into "dep" which links into "subdep"', async () => {
    expect.assertions(1);

    const expecting = expect.stringMatching('subdep');

    const x = await p.esy('x symlinks-into-dep');
    expect(x.stdout).toEqual(expecting);
  });

  it('check that link is here', async () => {
    const depFolder = await fs
      .readdir(path.join(p.projectPath, '../esy/3/i'))
      .then(dir => dir.filter(d => d.includes('dep-1.0.0'))[0]);

    const storeTarget = await fs.readlink(
      path.join(p.projectPath, '../esy/3/i', depFolder, '/bin/dep'),
    );

    expect(storeTarget).toEqual(expect.stringMatching(p.esyPrefixPath));
  });

  it('export build from store', async () => {
    expect.assertions(3);
    // export build from store
    // TODO: does this work in windows?
    await p.esy('export-build ../esy/3/i/dep-1.0.0-*');

    const tarFile = await fs
      .readdir(path.join(p.projectPath, '_export'))
      .then(dir => dir.filter(d => d.includes('.tar.gz'))[0]);

    await tar.x({
      gzip: true,
      cwd: path.join(p.projectPath, '_export'),
      file: path.join(p.projectPath, '_export', tarFile),
    });

    // check symlink target for exported build
    const buildFolder = tarFile.split('.tar.gz')[0];
    const exportedTarget = await fs.readlink(
      path.join(p.projectPath, '_export', buildFolder, '/bin/dep'),
    );
    expect(exportedTarget).toEqual(expect.stringMatching('________'));

    // drop & import
    const delResult = await del(path.join(p.projectPath, '../esy/3/i', buildFolder), {
      force: true,
    });
    // Should delete 1 folder
    expect(delResult.length).toEqual(1);

    await p.esy('import-build ./_export/dep-1.0.0-*.tar.gz');

    // check symlink target for imported build
    const importedTarget = await fs.readlink(
      path.join(p.projectPath, '../esy/3/i', buildFolder, '/bin/dep'),
    );
    expect(importedTarget).toEqual(expect.stringMatching(p.esyPrefixPath));
  });
});
