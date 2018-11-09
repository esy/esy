// @flow

const outdent = require('outdent');
const helpers = require('../test/helpers.js');

const {file, dir, packageJson, dummyExecutable} = helpers;

helpers.skipSuiteOnWindows();

describe('complete workflow for esy sandboxes', () => {
  async function createTestSandbox() {
    const p = await helpers.createTestSandbox();

    // add ocaml package, required by opam sandboxes implicitly
    await p.defineNpmPackage({
      name: 'ocaml',
      version: '1.0.0',
      esy: {},
    });

    // add @esy-ocaml/substs package, required by opam sandboxes implicitly
    await p.defineNpmPackage({
      name: '@esy-ocaml/substs',
      version: '1.0.0',
      esy: {},
    });

    return p;
  }

  it('no dependencies', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {
          build: ['true'],
        },
      }),
    ];
    const p = await createTestSandbox();

    await p.fixture(...fixture);
    await p.esy('install');
    await p.esy('build');
  });

  it('no package name, no package version', async () => {
    const p = await createTestSandbox();
    const fixture = [
      packageJson({
        esy: {
          install: [
            "cp #{self.root / 'root'}.js #{self.bin / 'root'}.js",
            helpers.buildCommand(p, "#{self.bin / 'root'}.js"),
          ],
        },
      }),
      dummyExecutable('root'),
    ];
    await p.fixture(...fixture);
    await p.esy('install --skip-repository-update');
    await p.esy('build');
    const {stdout} = await p.esy('x root.cmd');
    expect(stdout.trim()).toEqual('__root__');
  });

  it('npm dependencies', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {
          dep: '*',
        },
      }),
    ];
    const p = await createTestSandbox();
    await p.fixture(...fixture);

    await p.defineNpmPackageOfFixture([
      packageJson({
        name: 'dep',
        version: '1.0.0',
        esy: {
          install: [
            'cp #{self.root / self.name}.js #{self.bin / self.name}.js',
            helpers.buildCommand(p, '#{self.bin / self.name}.js'),
          ],
        },
        dependencies: {
          ocaml: '*',
        },
      }),
      dummyExecutable('dep'),
    ]);

    await p.esy('install --skip-repository-update');
    await p.esy('build');

    {
      const {stdout} = await p.esy('dep.cmd');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('b dep.cmd');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('x dep.cmd');
      expect(stdout.trim()).toEqual('__dep__');
    }
  });

  it('opam dependencies', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {
          ocaml: '*',
          '@opam/dep': '*',
        },
        devDependencies: {
          ocaml: '*',
        },
      }),
    ];
    const p = await createTestSandbox();
    await p.fixture(...fixture);

    await p.defineOpamPackageOfFixture(
      {
        name: 'dep',
        version: '1',
        opam: outdent`
          opam-version: "1.2"
          build: [
            ${helpers.buildCommandInOpam('dep.js')}
          ]
          install: [
            ["cp" "dep.js" "%{bin}%/dep.js"]
            ["cp" "dep.cmd" "%{bin}%/dep.cmd"]
          ]
        `,
        url: null,
      },
      [dummyExecutable('dep')],
    );

    await p.esy('install --skip-repository-update');
    await p.esy('build');

    {
      const {stdout} = await p.esy('dep.cmd');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('b dep.cmd');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('x dep.cmd');
      expect(stdout.trim()).toEqual('__dep__');
    }
  });

  it('linking to opam dependency ("<dirname>.opam" manifest)', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {
          ocaml: '*',
          '@opam/dep': '*',
        },
        devDependencies: {
          ocaml: '*',
        },
        resolutions: {
          '@opam/dep': 'link:./dep',
        },
      }),
      dir(
        'dep',
        file(
          'dep.opam',
          outdent`
            opam-version: "1.2"
            build: [
              ${helpers.buildCommandInOpam('dep.js')}
            ]
            install: [
              ["cp" "dep.cmd" "%{bin}%/dep.cmd"]
              ["cp" "dep.js" "%{bin}%/dep.js"]
            ]
          `,
        ),
        dummyExecutable('dep'),
      ),
    ];
    const p = await createTestSandbox();
    await p.fixture(...fixture);

    await p.esy('install --skip-repository-update');
    await p.esy('build');

    {
      const {stdout} = await p.esy('dep.cmd');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('b dep.cmd');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('x dep.cmd');
      expect(stdout.trim()).toEqual('__dep__');
    }
  });

  it('linking to opam dependency ("opam" manifest)', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {
          ocaml: '*',
          '@opam/dep': '*',
        },
        devDependencies: {
          ocaml: '*',
        },
        resolutions: {
          '@opam/dep': 'link:./dep',
        },
      }),
      dir(
        'dep',
        file(
          'opam',
          outdent`
            opam-version: "1.2"
            build: [
              ${helpers.buildCommandInOpam('dep.js')}
            ]
            install: [
              ["cp" "dep.js" "%{bin}%/dep.js"]
              ["cp" "dep.cmd" "%{bin}%/dep.cmd"]
            ]

          `,
        ),
        dummyExecutable('dep'),
      ),
    ];
    const p = await createTestSandbox();
    await p.fixture(...fixture);

    await p.esy('install --skip-repository-update');
    await p.esy('build');

    {
      const {stdout} = await p.esy('dep.cmd');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('b dep.cmd');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('x dep.cmd');
      expect(stdout.trim()).toEqual('__dep__');
    }
  });

  it('linking to opam dependency (custom manifest)', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {
          ocaml: '*',
          '@opam/dep': '*',
        },
        resolutions: {
          '@opam/dep': 'link:./dep/custom.opam',
        },
      }),
      dir(
        'dep',
        file(
          'custom.opam',
          outdent`
            opam-version: "1.2"
            build: [
              ${helpers.buildCommandInOpam('dep.js')}
            ]
            install: [
              ["cp" "dep.cmd" "%{bin}%/dep.cmd"]
              ["cp" "dep.js" "%{bin}%/dep.js"]
            ]

          `,
        ),
        dummyExecutable('dep'),
      ),
    ];
    const p = await createTestSandbox();
    await p.fixture(...fixture);

    await p.esy('install --skip-repository-update');
    await p.esy('build');

    {
      const {stdout} = await p.esy('dep.cmd');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('b dep.cmd');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('x dep.cmd');
      expect(stdout.trim()).toEqual('__dep__');
    }
  });

  it('allows to define just dependencies', async () => {
    const fixture = [
      packageJson({
        dependencies: {
          dep: '*',
        },
      }),
    ];
    const p = await createTestSandbox();
    await p.fixture(...fixture);

    await p.defineNpmPackageOfFixture([
      packageJson({
        name: 'dep',
        version: '1.0.0',
        esy: {
          install: [
            'cp #{self.root / self.name}.js #{self.bin / self.name}.js',
            helpers.buildCommand(p, '#{self.bin / self.name}.js'),
          ],
        },
        dependencies: {
          ocaml: '*',
        },
      }),
      dummyExecutable('dep'),
    ]);

    await p.esy('install --skip-repository-update');
    await p.esy('build');

    {
      const {stdout} = await p.esy('dep.cmd');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('b dep.cmd');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('x dep.cmd');
      expect(stdout.trim()).toEqual('__dep__');
    }
  });

  it('should not run postinstall if esy.json is present', async () => {
    const p = await createTestSandbox();
    await p.fixture(
      packageJson({
        dependencies: {
          dep: '*',
        },
      }),
    );

    await p.defineNpmPackageOfFixture([
      packageJson({
        name: 'dep',
        version: '1.0.0',
        scripts: {
          postinstall: 'false',
        },
      }),
      file('esy.json', '{}'),
    ]);

    await p.esy('install --skip-repository-update');
  });

  it('should not run postinstall if esy config is present in package.json', async () => {
    const p = await createTestSandbox();
    await p.fixture(
      packageJson({
        dependencies: {
          dep: '*',
        },
      }),
    );

    await p.defineNpmPackageOfFixture([
      packageJson({
        name: 'dep',
        version: '1.0.0',
        esy: {},
        scripts: {
          postinstall: 'false',
        },
      }),
    ]);

    await p.esy('install --skip-repository-update');
  });
});
