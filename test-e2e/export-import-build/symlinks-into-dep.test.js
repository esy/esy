// @flow

const path = require('path');
const fs = require('fs-extra');
const tar = require('tar');
const del = require('del');

const helpers = require('../test/helpers');
const {packageJson, dir, file, dummyExecutable} = helpers;

helpers.skipSuiteOnWindows('Needs investigation');

function makeFixture(p) {
  return [
    packageJson({
      name: 'app',
      version: '1.0.0',
      license: 'MIT',
      esy: {
        build: ['ln -s #{dep.bin / dep.name}.exe #{self.bin / self.name}.exe'],
      },
      dependencies: {
        dep: '*',
      },
    }),
    dir(
      'node_modules',
      dir(
        'dep',
        packageJson({
          name: 'dep',
          version: '1.0.0',
          license: 'MIT',
          esy: {
            build: ['ln -s #{subdep.bin / subdep.name}.exe #{self.bin / self.name}.exe'],
          },
          dependencies: {
            subdep: '*',
          },
        }),
        file('_esylink', JSON.stringify({source: `path:.`})),
        dir(
          'node_modules',
          dir(
            'subdep',
            packageJson({
              name: 'subdep',
              version: '1.0.0',
              license: 'MIT',
              esy: {
                buildsInSource: true,
                build: 'chmod +x #{self.name}.exe',
                install: 'cp #{self.name}.exe #{self.bin / self.name}.exe',
              },
            }),
            file('_esylink', JSON.stringify({source: `path:.`})),
            dummyExecutable('subdep'),
          ),
        ),
      ),
    ),
  ];
}

describe('export import build - import app', () => {
  let p;

  beforeEach(async () => {
    p = await helpers.createTestSandbox();
    await p.fixture(...makeFixture(p));
    await p.esy('build');
  });

  it('package "subdep" should be visible in all envs', async () => {
    const subdep = await p.esy('subdep.exe');
    expect(subdep.stdout.trim()).toEqual('__subdep__');
    const b = await p.esy('b subdep.exe');
    expect(b.stdout.trim()).toEqual('__subdep__');
    const x = await p.esy('x subdep.exe');
    expect(x.stdout.trim()).toEqual('__subdep__');
  });

  it('same for package "dep" but it should reuse the impl of "subdep"', async () => {
    const expecting = expect.stringMatching('subdep');

    const subdep = await p.esy('dep.exe');
    expect(subdep.stdout.trim()).toEqual('__subdep__');
    const b = await p.esy('b dep.exe');
    expect(b.stdout.trim()).toEqual('__subdep__');
    const x = await p.esy('x dep.exe');
    expect(x.stdout.trim()).toEqual('__subdep__');
  });

  it('and root package links into "dep" which links into "subdep"', async () => {
    const expecting = expect.stringMatching('subdep');

    const x = await p.esy('x app.exe');
    expect(x.stdout.trim()).toEqual('__subdep__');
  });

  it('check that link is here', async () => {
    const depFolder = await fs
      .readdir(path.join(p.projectPath, '../esy/3/i'))
      .then(dir => dir.filter(d => d.includes('dep-1.0.0'))[0]);

    const storeTarget = await fs.readlink(
      path.join(p.projectPath, '../esy/3/i', depFolder, '/bin/dep.exe'),
    );

    expect(storeTarget).toEqual(expect.stringMatching(p.esyPrefixPath));
  });

  it('export build from store', async () => {
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
      path.join(p.projectPath, '_export', buildFolder, '/bin/dep.exe'),
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
      path.join(p.projectPath, '../esy/3/i', buildFolder, '/bin/dep.exe'),
    );
    expect(importedTarget).toEqual(expect.stringMatching(p.esyPrefixPath));
  });
});
