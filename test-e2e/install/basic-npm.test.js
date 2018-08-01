/* @flow */

const path = require('path');
const helpers = require('../test/helpers.js');

helpers.skipSuiteOnWindows();

describe(`Basic tests for npm packages`, () => {
  test(`it should correctly install a single dependency that contains no sub-dependencies`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {[`no-deps`]: `1.0.0`},
      }),
    ];

    const p = await helpers.createTestSandbox(...fixture);
    await p.esy('install');

    await expect(
      p.runJavaScriptInNodeAndReturnJson(`require('no-deps')`),
    ).resolves.toMatchObject({
      name: `no-deps`,
      version: `1.0.0`,
    });
  });

  test(`it should correctly install a dependency that itself contains a fixed dependency`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {[`one-fixed-dep`]: `1.0.0`},
      }),
    ];

    const p = await helpers.createTestSandbox(...fixture);
    await p.esy('install');

    await expect(
      p.runJavaScriptInNodeAndReturnJson(`require('one-fixed-dep')`),
    ).resolves.toMatchObject({
      name: `one-fixed-dep`,
      version: `1.0.0`,
      dependencies: {
        [`no-deps`]: {
          name: `no-deps`,
          version: `1.0.0`,
        },
      },
    });
  });

  test(`it should correctly install a dependency that itself contains a range dependency`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {[`one-range-dep`]: `1.0.0`},
      }),
    ];

    const p = await helpers.createTestSandbox(...fixture);
    await p.esy('install');

    await expect(
      p.runJavaScriptInNodeAndReturnJson(`require('one-range-dep')`),
    ).resolves.toMatchObject({
      name: `one-range-dep`,
      version: `1.0.0`,
      dependencies: {
        [`no-deps`]: {
          name: `no-deps`,
          version: `1.1.0`,
        },
      },
    });
  });

  test(`it should correctly install bin wrappers into node_modules/.bin (single bin)`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {[`dep`]: `1.0.0`},
      }),
    ];

    const p = await helpers.createTestSandbox(...fixture);

    await p.defineNpmPackage({
      name: 'depDep',
      version: '1.0.0',
      dependencies: {depDep: `1.0.0`},
      bin: './depDep.exe',
    });

    const depPath = await p.defineNpmPackage({
      name: 'dep',
      version: '1.0.0',
      dependencies: {depDep: `1.0.0`},
      bin: './dep.exe',
    });

    await helpers.makeFakeBinary(path.join(depPath, 'dep.exe'), {
      exitCode: 0,
      output: 'HELLO',
    });

    await p.esy('install');

    const binPath = path.join(p.projectPath, 'node_modules', '.bin', 'dep');
    expect(await helpers.exists(binPath)).toBeTruthy();

    const proc = await helpers.execFile(binPath, [], {});
    expect(proc.stdout.toString().trim()).toBe('HELLO');

    // only root deps has their bin installed
    expect(
      await helpers.exists(path.join(p.projectPath, 'node_modules', '.bin', 'depDep')),
    ).toBeFalsy();
  });

  test(`it should correctly install bin wrappers into node_modules/.bin (multiple bins)`, async () => {
    const fixture = [
      helpers.packageJson({
        name: 'root',
        version: '1.0.0',
        dependencies: {[`dep`]: `1.0.0`},
      }),
    ];
    const p = await helpers.createTestSandbox(...fixture);
    await p.defineNpmPackage({
      name: 'depDep',
      version: '1.0.0',
      dependencies: {depDep: `1.0.0`},
      bin: './depDep.exe',
    });
    const depPath = await p.defineNpmPackage({
      name: 'dep',
      version: '1.0.0',
      dependencies: {depDep: `1.0.0`},
      bin: {
        dep: './dep.exe',
        dep2: './dep2.exe',
      },
    });

    await helpers.makeFakeBinary(path.join(depPath, 'dep.exe'), {
      exitCode: 0,
      output: 'HELLO',
    });
    await helpers.makeFakeBinary(path.join(depPath, 'dep2.exe'), {
      exitCode: 0,
      output: 'HELLO2',
    });

    await p.esy(`install`);

    {
      const binPath = path.join(p.projectPath, 'node_modules', '.bin', 'dep');
      expect(await helpers.exists(binPath)).toBeTruthy();

      const proc = await helpers.execFile(binPath, [], {});
      expect(proc.stdout.toString().trim()).toBe('HELLO');
    }

    {
      const binPath = path.join(p.projectPath, 'node_modules', '.bin', 'dep2');
      expect(await helpers.exists(binPath)).toBeTruthy();

      const proc = await helpers.execFile(binPath, [], {});
      expect(proc.stdout.toString().trim()).toBe('HELLO2');
    }

    // only root deps has their bin installed
    expect(
      await helpers.exists(path.join(p.projectPath, 'node_modules', '.bin', 'depDep')),
    ).toBeFalsy();
  });

  // test.skip(
  //   `it should correctly install an inter-dependency loop`,
  //   helpers.makeTemporaryEnv(
  //     {
  //       name: 'root',
  //       version: '1.0.0',
  //       dependencies: {[`dep-loop-entry`]: `1.0.0`},
  //     },
  //     async ({path, run, source}) => {
  //       await run(`install`);

  //       await expect(
  //         source(
  //           // eslint-disable-next-line
  //           `require('dep-loop-entry') === require('dep-loop-entry').dependencies['dep-loop-exit'].dependencies['dep-loop-entry']`,
  //         ),
  //       );
  //     },
  //   ),
  // );

  // test.skip(
  //   `it should install from archives on the filesystem`,
  //   helpers.makeTemporaryEnv(
  //     {
  //       name: 'root',
  //       version: '1.0.0',
  //       dependencies: {[`no-deps`]: helpers.getPackageArchivePath(`no-deps`, `1.0.0`)},
  //     },
  //     async ({path, run, source}) => {
  //       await run(`install`);

  //       await expect(source(`require('no-deps')`)).resolves.toMatchObject({
  //         name: `no-deps`,
  //         version: `1.0.0`,
  //       });
  //     },
  //   ),
  // );

  // test.skip(
  //   `it should install the dependencies of any dependency fetched from the filesystem`,
  //   helpers.makeTemporaryEnv(
  //     {
  //       name: 'root',
  //       version: '1.0.0',
  //       dependencies: {
  //         [`one-fixed-dep`]: helpers.getPackageArchivePath(`one-fixed-dep`, `1.0.0`),
  //       },
  //     },
  //     async ({path, run, source}) => {
  //       await run(`install`);

  //       await expect(source(`require('one-fixed-dep')`)).resolves.toMatchObject({
  //         name: `one-fixed-dep`,
  //         version: `1.0.0`,
  //         dependencies: {
  //           [`no-deps`]: {
  //             name: `no-deps`,
  //             version: `1.0.0`,
  //           },
  //         },
  //       });
  //     },
  //   ),
  // );

  // test.skip(
  //   `it should install from files on the internet`,
  //   helpers.makeTemporaryEnv(
  //     {
  //       name: 'root',
  //       version: '1.0.0',
  //       dependencies: {
  //         [`no-deps`]: helpers.getPackageHttpArchivePath(`no-deps`, `1.0.0`),
  //       },
  //     },
  //     async ({path, run, source}) => {
  //       await run(`install`);

  //       await expect(source(`require('no-deps')`)).resolves.toMatchObject({
  //         name: `no-deps`,
  //         version: `1.0.0`,
  //       });
  //     },
  //   ),
  // );

  // test.skip(
  //   `it should install the dependencies of any dependency fetched from the internet`,
  //   helpers.makeTemporaryEnv(
  //     {
  //       name: 'root',
  //       version: '1.0.0',
  //       dependencies: {
  //         [`one-fixed-dep`]: helpers.getPackageHttpArchivePath(`one-fixed-dep`, `1.0.0`),
  //       },
  //     },
  //     async ({path, run, source}) => {
  //       await run(`install`);

  //       await expect(source(`require('one-fixed-dep')`)).resolves.toMatchObject({
  //         name: `one-fixed-dep`,
  //         version: `1.0.0`,
  //         dependencies: {
  //           [`no-deps`]: {
  //             name: `no-deps`,
  //             version: `1.0.0`,
  //           },
  //         },
  //       });
  //     },
  //   ),
  // );

  // test.skip(
  //   `it should install from local directories`,
  //   helpers.makeTemporaryEnv(
  //     {
  //       name: 'root',
  //       version: '1.0.0',
  //       dependencies: {[`no-deps`]: helpers.getPackageDirectoryPath(`no-deps`, `1.0.0`)},
  //     },
  //     async ({path, run, source}) => {
  //       await run(`install`);

  //       await expect(source(`require('no-deps')`)).resolves.toMatchObject({
  //         name: `no-deps`,
  //         version: `1.0.0`,
  //       });
  //     },
  //   ),
  // );

  // test.skip(
  //   `it should install the dependencies of any dependency fetched from a local directory`,
  //   helpers.makeTemporaryEnv(
  //     {
  //       name: 'root',
  //       version: '1.0.0',
  //       dependencies: {
  //         [`one-fixed-dep`]: helpers.getPackageDirectoryPath(`one-fixed-dep`, `1.0.0`),
  //       },
  //     },
  //     async ({path, run, source}) => {
  //       await run(`install`);

  //       await expect(source(`require('one-fixed-dep')`)).resolves.toMatchObject({
  //         name: `one-fixed-dep`,
  //         version: `1.0.0`,
  //         dependencies: {
  //           [`no-deps`]: {
  //             name: `no-deps`,
  //             version: `1.0.0`,
  //           },
  //         },
  //       });
  //     },
  //   ),
  // );
});
