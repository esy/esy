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
  async function createTestSandbox() {
    const p = await helpers.createTestSandbox(...fixture);

    const esy = args =>
      p.esy(`${args}`, {
        cwd: path.join(p.projectPath, 'app'),
      });

    await esy('install');
    await esy('build');

    return {...p, esy};
  }

  it('works without changes', async () => {
    const p = await createTestSandbox();
    const dep = await p.esy('dep.cmd');
    expect(dep.stdout.trim()).toEqual('__dep__');
    const anotherDep = await p.esy('anotherDep.cmd');
    expect(anotherDep.stdout.trim()).toEqual('__anotherDep__');
  });

  it('works with modified dep sources', async () => {
    const p = await createTestSandbox();

    // wait, on macOS sometimes it doesn't pick up changes
    await new Promise(resolve => setTimeout(resolve, 500));

    await fs.writeFile(
      path.join(p.projectPath, 'dep', 'dep.js'),
      outdent`
        console.log('MODIFIED!');
      `,
    );

    await p.esy('build');
    const dep = await p.esy('dep.cmd');
    expect(dep.stdout.trim()).toEqual('MODIFIED!');
  });
});
