// @flow

const path = require('path');
const outdent = require('outdent');
const fs = require('fs-extra');
const helpers = require('../test/helpers');

const {file, dir, packageJson, dummyExecutable} = helpers;

helpers.skipSuiteOnWindows('Needs investigation');

describe('Symlink workflow', () => {
  async function createTestSandbox() {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      dir(
        'app',
        packageJson({
          name: 'app',
          version: '1.0.0',
          esy: {
            build: 'true',
          },
          dependencies: {
            dep: '*',
            anotherDep: '*',
          },
          resolutions: {
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
              helpers.buildCommand(p, '#{self.target_dir / self.name}.js'),
            ],
            install: [
              ['cp', '#{self.target_dir / self.name}.js', '#{self.bin / self.name}.js'],
              ['cp', '#{self.target_dir / self.name}.cmd', '#{self.bin / self.name}.cmd'],
            ],
          },
          dependencies: {anotherDep: '*'},
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
              helpers.buildCommand(p, '#{self.target_dir / self.name}.js'),
            ],
            install: [
              ['cp', '#{self.target_dir / self.name}.cmd', '#{self.bin / self.name}.cmd'],
              ['cp', '#{self.target_dir / self.name}.js', '#{self.bin / self.name}.js'],
            ],
          },
        }),
        dummyExecutable('anotherDep'),
      ),
    );

    p.cd('./app');

    return p;
  }

  it('works without changes', async () => {
    const p = await createTestSandbox();

    await p.esy('install');

    {
      // initial build builds everything
      const {stderr} = await p.esy('build');

      expect(stderr).toContain('info building anotherDep@link:../anotherDep');
      expect(stderr).toContain('info building dep@link:../dep');
    }

    {
      // second build builds nothing
      const {stderr} = await p.esy('build');

      expect(stderr).not.toContain('info building anotherDep@link:../anotherDep');
      expect(stderr).not.toContain('info building dep@link:../dep');
    }

    {
      // builds again if we pass --skip-staleness-check
      const {stderr} = await p.esy('build --skip-staleness-check');

      expect(stderr).toContain('info building anotherDep@link:../anotherDep');
      expect(stderr).toContain('info building dep@link:../dep');
    }

    const dep = await p.esy('dep.cmd');
    expect(dep.stdout.trim()).toEqual('__dep__');
    const anotherDep = await p.esy('anotherDep.cmd');
    expect(anotherDep.stdout.trim()).toEqual('__anotherDep__');
  });

  it('works with modified dep sources', async () => {
    const p = await createTestSandbox();
    await p.esy('install');

    {
      // initial build builds everything
      const {stderr} = await p.esy('build');

      expect(stderr).toContain('info building anotherDep@link:../anotherDep');
      expect(stderr).toContain('info building dep@link:../dep');
    }

    {
      const dep = await p.esy('dep.cmd');
      expect(dep.stdout.trim()).toEqual('__dep__');
    }

    // wait, on macOS sometimes it doesn't pick up changes
    await new Promise(resolve => setTimeout(resolve, 1000));

    await fs.writeFile(
      path.join(p.projectPath, 'dep', 'dep.js'),
      outdent`
        console.log('MODIFIED!');
      `,
    );

    {
      // second build builds dep (it was changed)
      const {stderr} = await p.esy('build');

      expect(stderr).not.toContain('info building anotherDep@link:../anotherDep');
      expect(stderr).toContain('info building dep@link:../dep');
    }

    {
      const dep = await p.esy('dep.cmd');
      expect(dep.stdout.trim()).toEqual('MODIFIED!');
    }
  });

  it('works with modified anotherDep sources', async () => {
    const p = await createTestSandbox();
    await p.esy('install');

    {
      // initial build builds everything
      const {stderr} = await p.esy('build');

      expect(stderr).toContain('info building anotherDep@link:../anotherDep');
      expect(stderr).toContain('info building dep@link:../dep');
    }

    {
      const dep = await p.esy('anotherDep.cmd');
      expect(dep.stdout.trim()).toEqual('__anotherDep__');
    }

    // wait, on macOS sometimes it doesn't pick up changes
    await new Promise(resolve => setTimeout(resolve, 1000));

    await fs.writeFile(
      path.join(p.projectPath, 'anotherDep', 'anotherDep.js'),
      outdent`
        console.log('MODIFIED!');
      `,
    );

    {
      // second build builds anotherDep (it was changed) and dep (depends on anotherDep)
      const {stderr} = await p.esy('build');

      expect(stderr).toContain('info building anotherDep@link:../anotherDep');
      expect(stderr).toContain('info building dep@link:../dep');
    }

    {
      const dep = await p.esy('anotherDep.cmd');
      expect(dep.stdout.trim()).toEqual('MODIFIED!');
    }
  });

  it('turns all revdeps of linked deps into linked deps', async () => {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      dir(
        'app',
        packageJson({
          name: 'app',
          version: '1.0.0',
          esy: {
            build: 'true',
          },
          dependencies: {
            dep: '*',
            anotherDep: '*',
          },
          resolutions: {
            dep: 'path:../dep',
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
              helpers.buildCommand(p, '#{self.target_dir / self.name}.js'),
            ],
            install: [
              ['cp', '#{self.target_dir / self.name}.js', '#{self.bin / self.name}.js'],
              ['cp', '#{self.target_dir / self.name}.cmd', '#{self.bin / self.name}.cmd'],
            ],
          },
          dependencies: {anotherDep: '*'},
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
              helpers.buildCommand(p, '#{self.target_dir / self.name}.js'),
            ],
            install: [
              ['cp', '#{self.target_dir / self.name}.cmd', '#{self.bin / self.name}.cmd'],
              ['cp', '#{self.target_dir / self.name}.js', '#{self.bin / self.name}.js'],
            ],
          },
        }),
        dummyExecutable('anotherDep'),
      ),
    );

    p.cd('./app');

    await p.esy('install');

    {
      // initial build builds everything
      const {stderr} = await p.esy('build');

      expect(stderr).toContain('info building anotherDep@link:../anotherDep');
      expect(stderr).toContain('info building dep@path:../dep');
    }

    {
      const dep = await p.esy('anotherDep.cmd');
      expect(dep.stdout.trim()).toEqual('__anotherDep__');
    }

    // wait, on macOS sometimes it doesn't pick up changes
    await new Promise(resolve => setTimeout(resolve, 1000));

    await fs.writeFile(
      path.join(p.projectPath, 'anotherDep', 'anotherDep.js'),
      outdent`
        console.log('MODIFIED!');
      `,
    );

    {
      // second build builds anotherDep (it was changed) and dep (depends on anotherDep)
      const {stderr} = await p.esy('build');

      expect(stderr).toContain('info building anotherDep@link:../anotherDep');
      expect(stderr).toContain('info building dep@path:../dep');
    }

    {
      const dep = await p.esy('anotherDep.cmd');
      expect(dep.stdout.trim()).toEqual('MODIFIED!');
    }
  });
});
