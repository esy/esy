// @flow

const path = require('path');
const outdent = require('outdent');
const fs = require('fs-extra');
const helpers = require('../test/helpers');

const {file, dir, packageJson, dummyExecutable} = helpers;

helpers.skipSuiteOnWindows('Needs investigation');

const fixture = [
  dir(
    'app',
    packageJson({
      name: 'app',
      version: '1.0.0',
      esy: {
        build: 'true',
      },
      dependencies: {
        dep: 'link:../dep',
        anotherDep: 'link:../anotherDep',
      },
    }),
  ),
  dir(
    'dep',
    packageJson({
      name: 'dep',
      version: '1.0.0',
      esy: {
        build: [
          [
            'cp',
            '#{self.original_root / self.name}.js',
            '#{self.target_dir / self.name}.js',
          ],
          helpers.buildCommand('#{self.target_dir / self.name}.js'),
        ],
        install: [
          ['cp', '#{self.target_dir / self.name}.js', '#{self.bin / self.name}.js'],
          ['cp', '#{self.target_dir / self.name}.cmd', '#{self.bin / self.name}.cmd'],
        ],
      },
    }),
    dummyExecutable('dep'),
  ),
  dir(
    'anotherDep',
    packageJson({
      name: 'anotherDep',
      version: '1.0.0',
      license: 'MIT',
      esy: {
        build: [
          [
            'cp',
            '#{self.original_root / self.name}.js',
            '#{self.target_dir / self.name}.js',
          ],
          helpers.buildCommand('#{self.target_dir / self.name}.js'),
        ],
        install: [
          ['cp', '#{self.target_dir / self.name}.cmd', '#{self.bin / self.name}.cmd'],
          ['cp', '#{self.target_dir / self.name}.js', '#{self.bin / self.name}.js'],
        ],
      },
    }),
    dummyExecutable('anotherDep'),
  ),
];

describe('Symlink workflow', () => {
  let p;
  let appEsy;

  beforeEach(async () => {
    p = await helpers.createTestSandbox(...fixture);

    appEsy = args =>
      p.esy(`${args}`, {
        cwd: path.join(p.projectPath, 'app'),
      });

    await appEsy('install');
    await appEsy('build');
  });

  it('works without changes', async () => {
    const dep = await appEsy('dep.cmd');
    expect(dep.stdout.trim()).toEqual('__dep__');
    const anotherDep = await appEsy('anotherDep.cmd');
    expect(anotherDep.stdout.trim()).toEqual('__anotherDep__');
  });

  it('works with modified dep sources', async () => {
    await fs.writeFile(
      path.join(p.projectPath, 'dep', 'dep.js'),
      outdent`
        console.log('MODIFIED!');
      `,
    );

    // wait, on macOS sometimes it doesn't pick up changes
    await new Promise(resolve => setTimeout(resolve, 800));

    await appEsy('build');
    const dep = await appEsy('dep.cmd');
    expect(dep.stdout.trim()).toEqual('MODIFIED!');
  });
});
