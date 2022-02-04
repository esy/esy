// @flow

const outdent = require('outdent');
const helpers = require('../test/helpers.js');

async function defineOpamPackageOfFixture(sandbox, packageName, packageVersion, executableName, registryIndex) {
    if (registryIndex !== undefined) {
        await sandbox.defineOpamPackageOfFixtureInSecondaryRegistry(
            registryIndex,
            {
                name: packageName,
                version: packageVersion,
                opam: outdent`
          opam-version: "2.0"
          build: [
            ${helpers.buildCommandInOpam(`${executableName}.js`)}
            ["cp" "${executableName}.cmd" "%{bin}%/${executableName}.cmd"]
            ["cp" "${executableName}.js" "%{bin}%/${executableName}.js"]
          ]
        `,
            },
            [
                helpers.dummyExecutable(executableName),
            ],
        );
    } else {
        await sandbox.defineOpamPackageOfFixture(
            {
                name: packageName,
                version: packageVersion,
                opam: outdent`
              opam-version: "2.0"
              build: [
                ${helpers.buildCommandInOpam(`${executableName}.js`)}
                ["cp" "${executableName}.cmd" "%{bin}%/${executableName}.cmd"]
                ["cp" "${executableName}.js" "%{bin}%/${executableName}.js"]
              ]
            `,
            },
            [
                helpers.dummyExecutable(executableName),
            ],
        );
    }
}

describe('installing opam dependencies from multiple registries', () => {

    it('fetch & builds opam dependencies from primary opam repo', async () => {
        const p = await helpers.createTestSandbox();

        const opamRegirstryA = await p.createSecondaryOpamRegistry();
        const opamRegirstryB = await p.createSecondaryOpamRegistry();

        await p.fixture(
            helpers.packageJson({
                name: 'root',
                esy: {
                    opamRepositories: [
                        {
                            type: "local",
                            location: p.secondaryOpamRegistries[opamRegirstryA].registryPath
                        },
                        {
                            type: "local",
                            location: p.secondaryOpamRegistries[opamRegirstryB].registryPath
                        }
                    ]
                },
                dependencies: {
                    '@opam/pkg1': '*',
                }
            }),
        );

        await p.defineNpmPackage({
            name: '@esy-ocaml/substs',
            version: '0.0.0',
            esy: {},
        });

        await defineOpamPackageOfFixture(p, 'pkg1', '1.0.0', 'hello');

        await p.esy('install');
        await p.esy('build');

        {
            const { stdout } = await p.esy('x hello.cmd');
            expect(stdout.trim()).toEqual('__hello__');
        }
    });

    it('fetch & builds opam dependencies from secondary opam repo', async () => {
        const p = await helpers.createTestSandbox();

        const opamRegirstryA = await p.createSecondaryOpamRegistry();
        const opamRegirstryB = await p.createSecondaryOpamRegistry();

        await p.fixture(
            helpers.packageJson({
                name: 'root',
                esy: {
                    opamRepositories: [
                        {
                            type: "local",
                            location: p.secondaryOpamRegistries[opamRegirstryA].registryPath
                        },
                        {
                            type: "local",
                            location: p.secondaryOpamRegistries[opamRegirstryB].registryPath
                        }
                    ]
                },
                dependencies: {
                    '@opam/pkg2': '*',
                }
            }),
        );

        await p.defineNpmPackage({
            name: '@esy-ocaml/substs',
            version: '0.0.0',
            esy: {},
        });

        await defineOpamPackageOfFixture(p, 'pkg1', '1.0.0', 'hello');

        await defineOpamPackageOfFixture(p, 'pkg2', '1.0.0', 'bye', opamRegirstryA);

        await p.esy('install');
        await p.esy('build');

        {
            const { stdout } = await p.esy('x bye.cmd');
            expect(stdout.trim()).toEqual('__bye__');
        }
    });

    it('fetch & builds opam dependencies from primary & multiple secondary opam repos', async () => {
        const p = await helpers.createTestSandbox();

        const opamRegirstryA = await p.createSecondaryOpamRegistry();
        const opamRegirstryB = await p.createSecondaryOpamRegistry();

        await p.fixture(
            helpers.packageJson({
                name: 'root',
                esy: {
                    opamRepositories: [
                        {
                            type: "local",
                            location: p.secondaryOpamRegistries[opamRegirstryA].registryPath
                        },
                        {
                            type: "local",
                            location: p.secondaryOpamRegistries[opamRegirstryB].registryPath
                        }
                    ]
                },
                dependencies: {
                    '@opam/pkg1': '*',
                    '@opam/pkg2': '*',
                    '@opam/pkg3': '*',
                }
            }),
        );

        await p.defineNpmPackage({
            name: '@esy-ocaml/substs',
            version: '0.0.0',
            esy: {},
        });

        await defineOpamPackageOfFixture(p, 'pkg1', '1.0.0', 'hello');

        await defineOpamPackageOfFixture(p, 'pkg2', '1.0.0', 'bye', opamRegirstryA);

        await defineOpamPackageOfFixture(p, 'pkg3', '1.0.0', 'foo', opamRegirstryB);

        await p.esy('install');
        await p.esy('build');

        {
            const { stdout: stdoutHello } = await p.esy('x hello.cmd');
            const { stdout: stdoutBye } = await p.esy('x bye.cmd');
            const { stdout: stdoutFoo } = await p.esy('x foo.cmd');

            expect(stdoutHello.trim()).toEqual('__hello__');
            expect(stdoutBye.trim()).toEqual('__bye__');
            expect(stdoutFoo.trim()).toEqual('__foo__');
        }
    });

    it('fetch & builds opam dependency of a same version from multiple opam repos', async () => {
        // Here the pkg1 (1.0.0) from opamRegirstryA gets higher priority

        const p = await helpers.createTestSandbox();

        const opamRegirstryA = await p.createSecondaryOpamRegistry();
        const opamRegirstryB = await p.createSecondaryOpamRegistry();

        await p.fixture(
            helpers.packageJson({
                name: 'root',
                esy: {
                    opamRepositories: [
                        {
                            type: "local",
                            location: p.secondaryOpamRegistries[opamRegirstryA].registryPath
                        },
                        {
                            type: "local",
                            location: p.secondaryOpamRegistries[opamRegirstryB].registryPath
                        }
                    ]
                },
                dependencies: {
                    '@opam/pkg1': '1.0.0',
                }
            }),
        );

        await p.defineNpmPackage({
            name: '@esy-ocaml/substs',
            version: '0.0.0',
            esy: {},
        });

        await defineOpamPackageOfFixture(p, 'pkg1', '1.0.0', 'hello');

        await defineOpamPackageOfFixture(p, 'pkg1', '1.0.0', 'bye', opamRegirstryA);

        await defineOpamPackageOfFixture(p, 'pkg1', '1.0.0', 'foo', opamRegirstryB);

        await p.esy('install');
        await p.esy('build');

        {
            const { stdout: stdoutBye } = await p.esy('x bye.cmd');

            expect(stdoutBye.trim()).toEqual('__bye__');
        }
    });

    it('fetch & builds opam dependency of a different versions(1.0.0) from multiple opam repos', async () => {
        const p = await helpers.createTestSandbox();

        const opamRegirstryA = await p.createSecondaryOpamRegistry();
        const opamRegirstryB = await p.createSecondaryOpamRegistry();

        await p.fixture(
            helpers.packageJson({
                name: 'root',
                esy: {
                    opamRepositories: [
                        {
                            type: "local",
                            location: p.secondaryOpamRegistries[opamRegirstryA].registryPath
                        },
                        {
                            type: "local",
                            location: p.secondaryOpamRegistries[opamRegirstryB].registryPath
                        }
                    ]
                },
                dependencies: {
                    '@opam/pkg1': '1.0.0',
                }
            }),
        );

        await p.defineNpmPackage({
            name: '@esy-ocaml/substs',
            version: '0.0.0',
            esy: {},
        });

        await defineOpamPackageOfFixture(p, 'pkg1', '1.0.0', 'hello');

        await defineOpamPackageOfFixture(p, 'pkg1', '2.0.0', 'bye', opamRegirstryA);

        await defineOpamPackageOfFixture(p, 'pkg1', '3.0.0', 'foo', opamRegirstryB);

        await p.esy('install');
        await p.esy('build');

        {
            const { stdout: stdoutHello } = await p.esy('x hello.cmd');

            expect(stdoutHello.trim()).toEqual('__hello__');
        }
    });

    it('fetch & builds opam dependency of a different versions(2.0.0) from multiple opam repos', async () => {
        const p = await helpers.createTestSandbox();

        const opamRegirstryA = await p.createSecondaryOpamRegistry();
        const opamRegirstryB = await p.createSecondaryOpamRegistry();

        await p.fixture(
            helpers.packageJson({
                name: 'root',
                esy: {
                    opamRepositories: [
                        {
                            type: "local",
                            location: p.secondaryOpamRegistries[opamRegirstryA].registryPath
                        },
                        {
                            type: "local",
                            location: p.secondaryOpamRegistries[opamRegirstryB].registryPath
                        }
                    ]
                },
                dependencies: {
                    '@opam/pkg1': '2.0.0',
                }
            }),
        );

        await p.defineNpmPackage({
            name: '@esy-ocaml/substs',
            version: '0.0.0',
            esy: {},
        });

        await defineOpamPackageOfFixture(p, 'pkg1', '1.0.0', 'hello');

        await defineOpamPackageOfFixture(p, 'pkg1', '2.0.0', 'bye', opamRegirstryA);

        await defineOpamPackageOfFixture(p, 'pkg1', '3.0.0', 'foo', opamRegirstryB);

        await p.esy('install');
        await p.esy('build');

        {
            const { stdout: stdoutBye } = await p.esy('x bye.cmd');

            expect(stdoutBye.trim()).toEqual('__bye__');
        }
    });

    it('fetch & builds opam dependency of a different versions(3.0.0) from multiple opam repos', async () => {
        const p = await helpers.createTestSandbox();

        const opamRegirstryA = await p.createSecondaryOpamRegistry();
        const opamRegirstryB = await p.createSecondaryOpamRegistry();

        await p.fixture(
            helpers.packageJson({
                name: 'root',
                esy: {
                    opamRepositories: [
                        {
                            type: "local",
                            location: p.secondaryOpamRegistries[opamRegirstryA].registryPath
                        },
                        {
                            type: "local",
                            location: p.secondaryOpamRegistries[opamRegirstryB].registryPath
                        }
                    ]
                },
                dependencies: {
                    '@opam/pkg1': '3.0.0',
                }
            }),
        );

        await p.defineNpmPackage({
            name: '@esy-ocaml/substs',
            version: '0.0.0',
            esy: {},
        });

        await defineOpamPackageOfFixture(p, 'pkg1', '1.0.0', 'hello');

        await defineOpamPackageOfFixture(p, 'pkg1', '2.0.0', 'bye', opamRegirstryA);

        await defineOpamPackageOfFixture(p, 'pkg1', '3.0.0', 'foo', opamRegirstryB);

        await p.esy('install');
        await p.esy('build');

        {
            const { stdout: stdoutFoo } = await p.esy('x foo.cmd');

            expect(stdoutFoo.trim()).toEqual('__foo__');
        }
    });

})