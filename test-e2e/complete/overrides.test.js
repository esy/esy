// @flow

const outdent = require('outdent');
const helpers = require('../test/helpers.js');

const {file, dir, packageJson} = helpers;

helpers.skipSuiteOnWindows();

describe('complete workflow for esy sandboxes', () => {
  async function createTestSandbox(...fixture) {
    const p = await helpers.createTestSandbox(...fixture);

    // add ocaml package, required by opam sandboxes implicitly
    await p.defineNpmPackageOfFixture(helpers.ocamlPackage().items);

    // add @esy-ocaml/substs package, required by opam sandboxes implicitly
    await p.defineNpmPackage({
      name: '@esy-ocaml/substs',
      version: '1.0.0',
      esy: {},
    });

    return p;
  }

  it('turning a dir into esy package', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {
          ocaml: '*',
          dep: '*',
        },
        devDependencies: {
          ocaml: '*',
        },
        resolutions: {
          dep: {
            source: 'path:./dep',
            override: {
              build: [
                'cp dep.ml #{self.target_dir/}dep.ml',
                'ocamlopt -o #{self.target_dir/}dep.exe #{self.target_dir/}dep.ml',
              ],
              install: ['cp #{self.target_dir/}dep.exe #{self.bin/}dep.exe'],
              dependencies: {
                ocaml: '*',
              },
            },
          },
        },
      }),
      dir('dep', file('dep.ml', 'print_endline "__dep__"')),
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

  it('buildType override', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {
          ocaml: '*',
          dep: '*',
        },
        devDependencies: {
          ocaml: '*',
        },
        resolutions: {
          dep: {
            source: 'path:./dep',
            override: {
              buildsInSource: true,
              build: ['ocamlopt -o dep.exe dep.ml'],
              install: ['cp dep.exe #{self.bin/}dep.exe'],
              dependencies: {
                ocaml: '*',
              },
            },
          },
        },
      }),
      dir('dep', file('dep.ml', 'print_endline "__dep__"')),
    ];
    const p = await createTestSandbox(...fixture);

    await p.esy('install --skip-repository-update');
    await p.esy('build');

    const {stdout} = await p.esy('dep.exe');
    expect(stdout.trim()).toEqual('__dep__');
  });

  it('turning a linked dir into esy package', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {
          ocaml: '*',
          dep: '*',
        },
        devDependencies: {
          ocaml: '*',
        },
        resolutions: {
          dep: {
            source: 'link:./dep',
            override: {
              build: [
                'cp dep.ml #{self.target_dir/}dep.ml',
                'ocamlopt -o #{self.target_dir/}dep.exe #{self.target_dir/}dep.ml',
              ],
              install: ['cp #{self.target_dir/}dep.exe #{self.bin/}dep.exe'],
              dependencies: {
                ocaml: '*',
              },
            },
          },
        },
      }),
      dir('dep', file('dep.ml', 'print_endline "__dep__"')),
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

  it('handles buildEnv', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {
          ocaml: '*',
          dep: '*',
        },
        devDependencies: {
          ocaml: '*',
        },
        resolutions: {
          dep: {
            source: 'path:./dep',
            override: {
              buildEnv: {DEPNAME: 'newdep'},
            },
          },
        },
      }),
      dir(
        'dep',
        packageJson({
          name: 'dep',
          version: '1.0.0',
          esy: {
            build: [
              'cp dep.ml #{self.target_dir/}dep.ml',
              'ocamlopt -o #{self.target_dir/}dep.exe #{self.target_dir/}dep.ml',
            ],
            buildEnv: {
              SHOULD_BE_DROPPED: 'OOPS',
            },
            install: ['cp #{self.target_dir/}dep.exe #{self.bin / $DEPNAME}.exe'],
          },
          dependencies: {ocaml: '*'},
        }),
        file('dep.ml', 'print_endline "__dep__"'),
      ),
    ];
    const p = await createTestSandbox(...fixture);

    await p.esy('install --skip-repository-update');
    await p.esy('build');

    {
      const {stdout} = await p.esy('newdep.exe');
      expect(stdout.trim()).toEqual('__dep__');
    }

    {
      const {stdout} = await p.esy('build-env --json _esy/default/node_modules/dep');
      const buildEnv = JSON.parse(stdout);
      expect(buildEnv.SHOULD_BE_DROPPED).toBeUndefined();
    }
  });

  it('handles buildEnvOverride', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {
          ocaml: '*',
          dep: '*',
        },
        devDependencies: {
          ocaml: '*',
        },
        resolutions: {
          dep: {
            source: 'path:./dep',
            override: {
              buildEnvOverride: {
                DEPNAME: 'newdep',
                SHOULD_BE_DROPPED: null,
                SHOULD_BE_ADDED: 'YUP',
              },
            },
          },
        },
      }),
      dir(
        'dep',
        packageJson({
          name: 'dep',
          version: '1.0.0',
          esy: {
            buildEnv: {
              DEPNAME: 'dep',
              SHOULD_BE_DROPPED: 'OOPS',
            },
            build: [
              'cp dep.ml #{self.target_dir/}dep.ml',
              'ocamlopt -o #{self.target_dir/}dep.exe #{self.target_dir/}dep.ml',
            ],
            install: ['cp #{self.target_dir/}dep.exe #{self.bin / $DEPNAME}.exe'],
          },
          dependencies: {ocaml: '*'},
        }),
        file('dep.ml', 'print_endline "__dep__"'),
      ),
    ];
    const p = await createTestSandbox(...fixture);

    await p.esy('install --skip-repository-update');
    await p.esy('build');

    {
      const {stdout} = await p.esy('newdep.exe');
      expect(stdout.trim()).toEqual('__dep__');
    }

    {
      const {stdout} = await p.esy('build-env ./_esy/default/node_modules/dep --json');
      const buildEnv = JSON.parse(stdout);
      expect(buildEnv.SHOULD_BE_DROPPED).toBeUndefined();
      expect(buildEnv.SHOULD_BE_ADDED).toBe('YUP');
    }
  });

  it('handles exportedEnvOverride', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {
          ocaml: '*',
          dep: '*',
        },
        devDependencies: {
          ocaml: '*',
        },
        resolutions: {
          dep: {
            source: 'path:./dep',
            override: {
              exportedEnv: {
                DEPNAME: {val: 'newdep'},
                SHOULD_BE_ADDED: {val: 'YUP'},
              },
            },
          },
        },
      }),
      dir(
        'dep',
        packageJson({
          name: 'dep',
          version: '1.0.0',
          esy: {
            exportedEnv: {
              DEPNAME: {val: 'dep'},
              SHOULD_BE_DROPPED: {val: 'oops'},
            },
            build: [],
            install: [],
          },
          dependencies: {ocaml: '*'},
        }),
      ),
    ];
    const p = await createTestSandbox(...fixture);

    await p.esy('install --skip-repository-update');
    await p.esy('build');

    {
      const {stdout} = await p.esy('build-env --json');
      const buildEnv = JSON.parse(stdout);
      expect(buildEnv.DEPNAME).toBe('newdep');
      expect(buildEnv.SHOULD_BE_DROPPED).toBeUndefined();
      expect(buildEnv.SHOULD_BE_ADDED).toBe('YUP');
    }
  });

  it('handles exportedEnvOverride', async () => {
    const fixture = [
      packageJson({
        name: 'root',
        version: '1.0.0',
        esy: {},
        dependencies: {
          ocaml: '*',
          dep: '*',
        },
        devDependencies: {
          ocaml: '*',
        },
        resolutions: {
          dep: {
            source: 'path:./dep',
            override: {
              exportedEnvOverride: {
                DEPNAME: {val: 'newdep'},
                SHOULD_BE_DROPPED: null,
                SHOULD_BE_ADDED: {val: 'YUP'},
              },
            },
          },
        },
      }),
      dir(
        'dep',
        packageJson({
          name: 'dep',
          version: '1.0.0',
          esy: {
            exportedEnv: {
              DEPNAME: {val: 'newdep'},
              SHOULD_BE_DROPPED: {val: 'OOPS'},
            },
            build: [],
            install: [],
          },
          dependencies: {ocaml: '*'},
        }),
      ),
    ];
    const p = await createTestSandbox(...fixture);

    await p.esy('install --skip-repository-update');
    await p.esy('build');

    {
      const {stdout} = await p.esy('build-env --json');
      const buildEnv = JSON.parse(stdout);
      expect(buildEnv.DEPNAME).toBe('newdep');
      expect(buildEnv.SHOULD_BE_DROPPED).toBeUndefined();
      expect(buildEnv.SHOULD_BE_ADDED).toBe('YUP');
    }
  });
});
