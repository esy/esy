// @flow

const outdent = require('outdent');
const helpers = require('../test/helpers.js');

const {file, dir, packageJson, dummyExecutable} = helpers;

helpers.skipSuiteOnWindows();

describe('complete workflow for esy sandboxes', () => {
  async function createTestSandbox(...fixture) {
    const p = await helpers.createTestSandbox(...fixture);

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
    const p = await createTestSandbox(...fixture);
    await p.esy('install');
    await p.esy('build');
  });

  it('no package name, no package version', async () => {
    const fixture = [
      packageJson({
        esy: {
          install: [
            "cp #{self.root / 'root'}.exe #{self.bin / 'root'}.exe",
            "chmod +x #{self.bin / 'root'}.exe",
          ],
        },
      }),
      dummyExecutable('root'),
    ];
    const p = await createTestSandbox(...fixture);
    await p.esy('install --skip-repository-update');
    await p.esy('build');
    const {stdout} = await p.esy('x root.exe');
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
    const p = await createTestSandbox(...fixture);

    await p.defineNpmPackageOfFixture([
      packageJson({
        name: 'dep',
        version: '1.0.0',
        esy: {
          install: [
            'cp #{self.root / self.name}.exe #{self.bin / self.name}.exe',
            'chmod +x #{self.bin / self.name}.exe',
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
      const {stdout} = await p.esy('dep.exe');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('b dep.exe');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('x dep.exe');
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
    const p = await createTestSandbox(...fixture);

    await p.defineOpamPackageOfFixture(
      {
        name: 'dep',
        version: '1',
        opam: outdent`
          opam-version: "1.2"
          build: [
            ["chmod" "+x" "dep.exe"]
          ]
          install: [
            ["cp" "dep.exe" "%{bin}%/dep.exe"]
          ]
        `,
        url: null,
      },
      [dummyExecutable('dep')],
    );

    await p.esy('install --skip-repository-update');
    await p.esy('build');

    {
      const {stdout} = await p.esy('dep.exe');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('b dep.exe');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('x dep.exe');
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
          '@opam/dep': 'link:./dep',
        },
        devDependencies: {
          ocaml: '*',
        },
      }),
      dir(
        'dep',
        file(
          'dep.opam',
          outdent`
            opam-version: "1.2"
            build: [
              ["chmod" "+x" "dep.exe"]
            ]
            install: [
              ["cp" "dep.exe" "%{bin}%/dep.exe"]
            ]
          `,
        ),
        dummyExecutable('dep'),
      ),
    ];
    const p = await createTestSandbox(...fixture);

    await p.esy('install --skip-repository-update');
    await p.esy('build');

    {
      const {stdout} = await p.esy('dep.exe');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('b dep.exe');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('x dep.exe');
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
          '@opam/dep': 'link:./dep',
        },
        devDependencies: {
          ocaml: '*',
        },
      }),
      dir(
        'dep',
        file(
          'opam',
          outdent`
            opam-version: "1.2"
            build: [
              ["chmod" "+x" "dep.exe"]
            ]
            install: [
              ["cp" "dep.exe" "%{bin}%/dep.exe"]
            ]

          `,
        ),
        dummyExecutable('dep'),
      ),
    ];
    const p = await createTestSandbox(...fixture);

    await p.esy('install --skip-repository-update');
    await p.esy('build');

    {
      const {stdout} = await p.esy('dep.exe');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('b dep.exe');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('x dep.exe');
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
              ["chmod" "+x" "dep.exe"]
            ]
            install: [
              ["cp" "dep.exe" "%{bin}%/dep.exe"]
            ]

          `,
        ),
        dummyExecutable('dep'),
      ),
    ];
    const p = await createTestSandbox(...fixture);

    await p.esy('install --skip-repository-update');
    await p.esy('build');

    {
      const {stdout} = await p.esy('dep.exe');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('b dep.exe');
      expect(stdout.trim()).toEqual('__dep__');
    }
    {
      const {stdout} = await p.esy('x dep.exe');
      expect(stdout.trim()).toEqual('__dep__');
    }
  });
});
