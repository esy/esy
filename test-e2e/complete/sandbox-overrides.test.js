// @flow

const outdent = require('outdent');
const helpers = require('../test/helpers.js');
const {file, json, dummyExecutable} = helpers;

helpers.skipSuiteOnWindows("esy-solve-cudf isn't ready");

describe('Sandbox overrides', function() {
  it('allows to override sandbox with dependencies', async function() {
    const p = await helpers.createTestSandbox();

    await p.defineNpmPackage({
      name: 'dep',
      version: '1.0.0',
    });

    await p.defineNpmPackage({
      name: 'dep',
      version: '2.0.0',
    });

    await p.fixture(
      file(
        'package.json',
        JSON.stringify({
          name: 'root',
          dependencies: {
            dep: '1.0.0',
          },
        }),
      ),
      file(
        'another.json',
        JSON.stringify({
          source: 'path:./package.json',
          override: {
            dependencies: {
              dep: '2.0.0',
            },
          },
        }),
      ),
    );

    await p.esy('install');
    await p.esy('@another install');

    expect(await helpers.readInstalledPackages(p.projectPath, 'default')).toMatchObject({
      dependencies: {
        dep: {name: 'dep', version: '1.0.0'},
      },
    });

    expect(await helpers.readInstalledPackages(p.projectPath, 'another')).toMatchObject({
      dependencies: {
        dep: {name: 'dep', version: '2.0.0'},
      },
    });
  });

  it('allows to override sandbox with devDependencies', async function() {
    const p = await helpers.createTestSandbox();

    await p.defineNpmPackage({
      name: 'dep',
      version: '1.0.0',
    });

    await p.defineNpmPackage({
      name: 'dep',
      version: '2.0.0',
    });

    await p.fixture(
      file(
        'package.json',
        JSON.stringify({
          name: 'root',
          devDependencies: {
            dep: '1.0.0',
          },
        }),
      ),
      file(
        'another.json',
        JSON.stringify({
          source: 'path:./package.json',
          override: {
            devDependencies: {
              dep: '2.0.0',
            },
          },
        }),
      ),
    );

    await p.esy('install');
    await p.esy('@another install');

    expect(await helpers.readInstalledPackages(p.projectPath, 'default')).toMatchObject({
      devDependencies: {
        dep: {name: 'dep', version: '1.0.0'},
      },
    });

    expect(await helpers.readInstalledPackages(p.projectPath, 'another')).toMatchObject({
      devDependencies: {
        dep: {name: 'dep', version: '2.0.0'},
      },
    });
  });

  it('allows to override sandbox with resolutions', async function() {
    const p = await helpers.createTestSandbox();

    await p.defineNpmPackage({
      name: 'dep',
      version: '1.0.0',
    });

    await p.defineNpmPackage({
      name: 'dep',
      version: '2.0.0',
    });

    await p.fixture(
      file(
        'package.json',
        JSON.stringify({
          name: 'root',
          dependencies: {
            dep: '2.0.0',
          },
        }),
      ),
      file(
        'another.json',
        JSON.stringify({
          source: 'path:./package.json',
          override: {
            resolutions: {
              dep: '1.0.0',
            },
          },
        }),
      ),
    );

    await p.esy('install');
    await p.esy('@another install');

    expect(await helpers.readInstalledPackages(p.projectPath, 'default')).toMatchObject({
      dependencies: {
        dep: {name: 'dep', version: '2.0.0'},
      },
    });

    expect(await helpers.readInstalledPackages(p.projectPath, 'another')).toMatchObject({
      dependencies: {
        dep: {name: 'dep', version: '1.0.0'},
      },
    });
  });

  it('allows to override sandbox with build commands', async function() {
    const p = await helpers.createTestSandbox();

    // package.json is a sandbox config which defines hello.cmd printing
    // __one__, we want to override __one__ with __two__ in another.js

    await p.fixture(
      file(
        'package.json',
        JSON.stringify({
          name: 'root',
          esy: {
            build: [
              "cp one.js #{self.target_dir / 'hello.js'}",
              helpers.buildCommand(p, "#{self.target_dir / 'hello.js'}"),
            ],
            install: [
              "cp #{self.target_dir / 'hello.js'} #{self.bin / 'hello.js'}",
              "cp #{self.target_dir / 'hello.cmd'} #{self.bin / 'hello.cmd'}",
            ],
          },
        }),
      ),
      file(
        'another.json',
        JSON.stringify({
          source: 'path:./package.json',
          override: {
            build: [
              "cp two.js #{self.target_dir / 'hello.js'}",
              helpers.buildCommand(p, "#{self.target_dir / 'hello.js'}"),
            ],
          },
        }),
      ),
      dummyExecutable('one'),
      dummyExecutable('two'),
    );

    await p.esy('install');
    await p.esy('build');
    {
      const {stdout} = await p.esy('x hello.cmd');
      expect(stdout.trim()).toBe('__one__');
    }

    await p.esy('@another install');
    await p.esy('@another build');

    {
      const {stdout} = await p.esy('@another x hello.cmd');
      expect(stdout.trim()).toBe('__two__');
    }
  });

  it('allows to override sandbox with install commands', async function() {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      file(
        'package.json',
        JSON.stringify({
          name: 'root',
          esy: {
            build: [
              "cp hello.js #{self.target_dir / 'hello.js'}",
              helpers.buildCommand(p, "#{self.target_dir / 'hello.js'}"),
            ],
            install: [
              "cp #{self.target_dir / 'hello.js'} #{self.bin / 'hello.js'}",
              "cp #{self.target_dir / 'hello.cmd'} #{self.bin / 'hello.cmd'}",
            ],
          },
        }),
      ),
      file(
        'another.json',
        JSON.stringify({
          source: 'path:./package.json',
          override: {
            install: [
              "cp #{self.target_dir / 'hello.js'} #{self.bin / 'hello.js'}",
              "cp #{self.target_dir / 'hello.cmd'} #{self.bin / 'new-hello.cmd'}",
            ],
          },
        }),
      ),
      dummyExecutable('hello'),
    );

    await p.esy('install');
    await p.esy('build');
    {
      const {stdout} = await p.esy('x hello.cmd');
      expect(stdout.trim()).toBe('__hello__');
    }

    await p.esy('@another install');
    await p.esy('@another build');

    {
      const {stdout} = await p.esy('@another x new-hello.cmd');
      expect(stdout.trim()).toBe('__hello__');
    }
  });

  it('allows to override opam sandbox with devDependencies', async function() {
    const p = await helpers.createTestSandbox();

    await p.defineNpmPackage({
      name: 'devDep',
      version: '1.0.0',
      esy: {},
    });

    await p.defineNpmPackage({
      name: 'ocaml',
      version: '1.0.0',
      esy: {},
    });

    await p.defineNpmPackage({
      name: '@esy-ocaml/substs',
      version: '1.0.0',
      esy: {},
    });

    await p.fixture(
      json('package.json', {
        source: 'path:pkg.opam',
        override: {
          devDependencies: {devDep: '*'},
        },
      }),
      file(
        'pkg.opam',
        outdent`
        opam-version: "2.0"
        depends: []
        `,
      ),
    );

    await p.esy('install');
    expect(await helpers.readInstalledPackages(p.projectPath)).toMatchObject({
      dependencies: {
        '@esy-ocaml/substs': {name: '@esy-ocaml/substs'},
      },
      devDependencies: {
        devDep: {name: 'devDep'},
      },
    });
  });

  it('using relaxed source parsing when specifying sources', async function() {
    const p = await helpers.createTestSandbox();

    await p.defineNpmPackage({
      name: 'dep',
      version: '1.0.0',
    });

    await p.defineNpmPackage({
      name: 'dep',
      version: '2.0.0',
    });

    await p.fixture(
      file(
        'package.json',
        JSON.stringify({
          name: 'root',
          dependencies: {
            dep: '1.0.0',
          },
        }),
      ),
      file(
        'another.json',
        JSON.stringify({
          source: './package.json',
          override: {
            dependencies: {
              dep: '2.0.0',
            },
          },
        }),
      ),
    );

    await p.esy('install');
    await p.esy('@another install');

    expect(await helpers.readInstalledPackages(p.projectPath, 'default')).toMatchObject({
      dependencies: {
        dep: {name: 'dep', version: '1.0.0'},
      },
    });

    expect(await helpers.readInstalledPackages(p.projectPath, 'another')).toMatchObject({
      dependencies: {
        dep: {name: 'dep', version: '2.0.0'},
      },
    });
  });
});
