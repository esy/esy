// @flow

const path = require('path');
const del = require('del');
const fs = require('fs-extra');

const helpers = require('../test/helpers');
const {packageJson, dir, file, dummyExecutable} = helpers;

helpers.skipSuiteOnWindows('Needs investigation');

it('export import build - from list', async () => {
  const p = await helpers.createTestSandbox();

  await p.defineNpmPackageOfFixture([
    packageJson({
      name: 'subdep',
      version: '1.0.0',
      license: 'MIT',
      esy: {
        buildsInSource: true,
        build: [helpers.buildCommand(p, '#{self.name}.js')],
        install: [
          'cp #{self.name}.cmd #{self.bin / self.name}.cmd',
          'cp #{self.name}.js #{self.bin / self.name}.js',
        ],
      },
    }),
    dummyExecutable('subdep'),
  ]);

  await p.defineNpmPackageOfFixture([
    packageJson({
      name: 'dep',
      version: '1.0.0',
      license: 'MIT',
      esy: {
        build: ['ln -s #{subdep.bin / subdep.name}.cmd #{self.bin / self.name}.cmd'],
      },
      dependencies: {
        subdep: '*',
      },
    }),
  ]);

  await p.fixture(
    packageJson({
      name: 'app',
      version: '1.0.0',
      license: 'MIT',
      esy: {
        build: ['ln -s #{dep.bin / dep.name}.cmd #{self.bin / self.name}.cmd'],
      },
      dependencies: {
        dep: '*',
      },
    }),
  );

  await p.esy('install');
  await p.esy('build');

  await p.esy('export-dependencies');

  const list = await fs.readdir(path.join(p.projectPath, '_export'));

  await fs.writeFile(
    path.join(p.projectPath, 'list.txt'),
    list.map(x => path.join('_export', x)).join('\n') + '\n',
  );

  const expected = [
    expect.stringMatching('dep-1.0.0'),
    expect.stringMatching('subdep-1.0.0'),
  ];

  const delResult = await del(path.join(p.esyPrefixPath, '4_*', 'i', '*'), {force: true});
  expect(delResult).toEqual(expect.arrayContaining(expected));

  await p.esy('import-build --from ./list.txt');

  const ls = await fs.readdir(path.join(p.esyStorePath, 'i'));
  expect(ls).toEqual(expect.arrayContaining(expected));

  {
    const {stdout} = await p.esy('subdep.cmd');
    expect(stdout.trim()).toBe('__subdep__');
  }
  {
    const {stdout} = await p.esy('dep.cmd');
    expect(stdout.trim()).toBe('__subdep__');
  }
  {
    const {stdout} = await p.esy('x app.cmd');
    expect(stdout.trim()).toBe('__subdep__');
  }
});
