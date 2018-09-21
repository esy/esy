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
            '#{self.original_root / self.name}.exe',
            '#{self.target_dir / self.name}.exe',
          ],
          ['chmod', '+x', '#{self.target_dir / self.name}.exe'],
        ],
        install: [
          ['cp', '#{self.target_dir / self.name}.exe', '#{self.bin / self.name}.exe'],
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
            '#{self.original_root / self.name}.exe',
            '#{self.target_dir / self.name}.exe',
          ],
          ['chmod', '+x', '#{self.target_dir / self.name}.exe'],
        ],
        install: [
          ['cp', '#{self.target_dir / self.name}.exe', '#{self.bin / self.name}.exe'],
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
    const dep = await appEsy('dep.exe');
    expect(dep.stdout.trim()).toEqual('__dep__');
    const anotherDep = await appEsy('anotherDep.exe');
    expect(anotherDep.stdout.trim()).toEqual('__anotherDep__');
  });

  it('works with modified dep sources', async () => {
    await fs.writeFile(
      path.join(p.projectPath, 'dep', 'dep.exe'),
      outdent`
        #!${process.execPath}
        console.log('MODIFIED!');
      `,
    );

    await appEsy('build');
    const dep = await appEsy('dep.exe');
    expect(dep.stdout.trim()).toEqual('MODIFIED!');
  });
});
