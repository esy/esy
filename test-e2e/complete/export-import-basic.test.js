// @flow

const path = require('path');
const fs = require('fs-extra');

const helpers = require('../test/helpers');
const {packageJson, dir, file, dummyExecutable} = helpers;

helpers.skipSuiteOnWindows('Needs investigation');

it('basic export / import test', async () => {
  const p = await helpers.createTestSandbox();
  await p.fixture(
    packageJson({
      name: 'app',
      version: '1.0.0',
      license: 'MIT',
      esy: {
        build: ['ln -s #{dep.bin / dep.name}.cmd #{self.bin / self.name}.cmd'],
      },
      dependencies: {
        dep: 'path:dep',
      },
      devDependencies: {
        devdep: 'path:devdep',
      }
    }),
    dir(
      'dep',
      packageJson({
        name: 'dep',
        version: '1.0.0',
        license: 'MIT',
        esy: {
          build: ['ln -s #{subdep.bin / subdep.name}.cmd #{self.bin / self.name}.cmd'],
        },
        dependencies: {
          subdep: 'path:../subdep',
        },
      }),
    ),
    dir(
      'devdep',
      packageJson({
        name: 'devdep',
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
      dummyExecutable('devdep'),
    ),
    dir(
      'subdep',
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
    ),
  );

  await p.esy('install');
  await p.esy('build');

  await p.esy('export-dependencies');

  const exportPath = path.join(p.projectPath, '_export');

  expect(await fs.exists(exportPath)).toBeTruthy();

  const items = await fs.readdir(exportPath);

  // make sure we can import w/o store and local esy installation
  await fs.remove(p.esyPrefixPath);
  await fs.remove(path.join(p.projectPath, '_esy'));

  for (const item of items) {
    const buildPath = path.join(exportPath, item);
    await p.esy(`import-build ${buildPath}`);
  }

  await p.esy('install');

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
  {
    const {stdout} = await p.esy('devdep.cmd');
    expect(stdout.trim()).toBe('__devdep__');
  }
});
