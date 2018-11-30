// @flow

const helpers = require('../test/helpers');
const {test, isWindows, isMacos} = helpers;

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
  describe('builds w/o opt dependency installed', () => {
    async function createTestSandbox() {
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
      return p;
    }

    test('check build-plan', async () => {
      const p = await createTestSandbox();
      await p.esy('install');
      const plan = JSON.parse((await p.esy('build-plan dep@path:dep')).stdout);
      expect(plan.build).toEqual([['optDep.installed', 'false']]);
    });

    test.enableIf(isMacos)('snapshot build-env', async () => {
      const p = await createTestSandbox();
      await p.esy('install');

      {
        const id = JSON.parse((await p.esy('build-plan')).stdout).id;
        const {stdout} = await p.esy('build-env');
        expect(p.normalizePathsForSnapshot(stdout, {id})).toMatchSnapshot();
      }

      {
        const id = JSON.parse((await p.esy('build-plan dep')).stdout).id;
        const {stdout} = await p.esy('build-env dep');
        expect(p.normalizePathsForSnapshot(stdout, {id})).toMatchSnapshot();
      }
    });
  });

  describe('builds w/ opt dependency installed', () => {
    async function createTestSandbox() {
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

      return p;
    }

    test('check build-plan', async () => {
      const p = await createTestSandbox();
      await p.esy('install');
      const plan = JSON.parse((await p.esy('build-plan dep@path:dep')).stdout);
      expect(plan.build).toEqual([['optDep.installed', 'true']]);
    });

    test.enableIf(isMacos)('snapshot build-env', async () => {
      const p = await createTestSandbox();
      await p.esy('install');
      {
        const id = JSON.parse((await p.esy('build-plan')).stdout).id;
        const {stdout} = await p.esy('build-env');
        expect(p.normalizePathsForSnapshot(stdout, {id})).toMatchSnapshot();
      }

      {
        const id = JSON.parse((await p.esy('build-plan dep')).stdout).id;
        const {stdout} = await p.esy('build-env dep');
        expect(p.normalizePathsForSnapshot(stdout, {id})).toMatchSnapshot();
      }
    });
  });

  test('opam package builds w/ opt dependency installed', async () => {
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

  test('opam package builds w/o opt dependency installed', async () => {
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
