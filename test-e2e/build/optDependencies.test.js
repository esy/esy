// @flow

const helpers = require('../test/helpers');

function makePackage(p, {name, build, dependencies, optDependencies}, ...children) {
  return [
    helpers.packageJson({
      name: name,
      version: '1.0.0',
      esy: {
        build,
      },
      dependencies,
      optDependencies,
    }),
    ...children,
  ];
}

describe('Build with optDependencies', () => {
  it('builds w/o opt dependency installed', async () => {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      ...makePackage(
        p,
        {
          name: 'root',
          build: 'true',
          dependencies: {
            dep: 'path:./dep',
          },
          optDependencies: {},
        },
        helpers.dir(
          'dep',
          ...makePackage(p, {
            name: 'dep',
            build: 'optDep.installed #{optDep.installed}',
            dependencies: {},
            optDependencies: {optDep: '*'},
          }),
        ),
      ),
    );

    await p.esy('install');
    const plan = JSON.parse((await p.esy('build-plan dep@path:dep')).stdout);
    expect(plan.build).toEqual([['optDep.installed', 'false']]);
  });

  it('builds w/ opt dependency installed', async () => {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      ...makePackage(
        p,
        {
          name: 'root',
          build: 'true',
          dependencies: {
            dep: 'path:./dep',
            optDep: 'path:./optDep',
          },
          optDependencies: {},
        },
        helpers.dir(
          'dep',
          ...makePackage(p, {
            name: 'dep',
            build: 'optDep.installed #{optDep.installed}',
            dependencies: {},
            optDependencies: {optDep: '*'},
          }),
        ),
        helpers.dir(
          'optDep',
          ...makePackage(p, {
            name: 'optDep',
            build: 'true',
            dependencies: {},
            optDependencies: {},
          }),
        ),
      ),
    );

    await p.esy('install');
    const plan = JSON.parse((await p.esy('build-plan dep@path:dep')).stdout);
    expect(plan.build).toEqual([['optDep.installed', 'true']]);
  });

  it('opam package builds w/ opt dependency installed', async () => {
    const p = await helpers.createTestSandbox();

    await p.defineNpmPackage({
      name: '@esy-ocaml/substs',
      version: '1.0.0',
      esy: {},
    });

    await p.defineOpamPackage({
      name: 'dep',
      version: '1.0.0',
      opam: `
      opam-version: "2.0"
      build: [
        ["optDep:installed" "%{optDep:installed}%"]
        ["optDep:enabled" "%{optDep:enabled}%"]
      ]
      depopts: ["optDep"]
      `,
      url: null,
    });

    await p.defineOpamPackage({
      name: 'optDep',
      version: '1.0.0',
      opam: `
      opam-version: "2.0"
      build: [
        "true"
      ]
      `,
      url: null,
    });

    await p.fixture(
      ...makePackage(p, {
        name: 'root',
        build: 'true',
        dependencies: {
          '@opam/dep': '*',
          '@opam/optDep': '*',
        },
        optDependencies: {},
      }),
    );

    await p.esy('install');
    const plan = JSON.parse((await p.esy('build-plan @opam/dep@opam:1.0.0')).stdout);
    expect(plan.build).toEqual([
      ['optDep:installed', 'true'],
      ['optDep:enabled', 'enable'],
    ]);
  });

  it('opam package builds w/o opt dependency installed', async () => {
    const p = await helpers.createTestSandbox();

    await p.defineNpmPackage({
      name: '@esy-ocaml/substs',
      version: '1.0.0',
      esy: {},
    });

    await p.defineOpamPackage({
      name: 'dep',
      version: '1.0.0',
      opam: `
      opam-version: "2.0"
      build: [
        ["optDep:installed" "%{optDep:installed}%"]
        ["optDep:enabled" "%{optDep:enabled}%"]
      ]
      depopts: ["optDep"]
      `,
      url: null,
    });

    await p.defineOpamPackage({
      name: 'optDep',
      version: '1.0.0',
      opam: `
      opam-version: "2.0"
      build: [
        "true"
      ]
      `,
      url: null,
    });

    await p.fixture(
      ...makePackage(p, {
        name: 'root',
        build: 'true',
        dependencies: {
          '@opam/dep': '*',
        },
        optDependencies: {},
      }),
    );

    await p.esy('install');
    const plan = JSON.parse((await p.esy('build-plan @opam/dep@opam:1.0.0')).stdout);
    expect(plan.build).toEqual([
      ['optDep:installed', 'false'],
      ['optDep:enabled', 'disable'],
    ]);
  });
});
