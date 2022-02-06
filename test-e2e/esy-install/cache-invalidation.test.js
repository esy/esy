// @flow

const outdent = require('outdent');
const helpers = require('../test/helpers.js');
const path = require('path');
const fs = require('../test/fs.js');
const FixtureUtils = require('../test/FixtureUtils.js');
const rimraf = require('rimraf');

describe(`'esy install': Cache invalidation`, () => {
  test(`opam override updates should be picked up`, async () => {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      helpers.packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          '@opam/dep': '*',
        },
      }),
    );

    await p.defineNpmPackage({
      name: '@esy-ocaml/substs',
      version: '0.0.0',
      esy: {},
    });

    await p.defineOpamPackageOfFixture(
      {
        name: 'dep',
        version: '1.0.0',
        opam: `
          opam-version: "1.2"
          build: [true]
          install: ["cp" "./hello" lib]
        `,
      },
      [helpers.file('hello', 'not-overridden')],
    );

    await p.esy(`install`);
    await p.esy(`build`);

    // check what we have w/o override
    {
      // Because of the way we split the args, on Windows, we need not quote esy command expressions
      let command =
        process.platform == 'win32'
          ? `cat #{@opam/dep.lib}/hello`
          : `cat '#{@opam/dep.lib}/hello'`;

      const {stdout} = await p.esy(command);
      expect(stdout.trim()).toBe('not-overridden');
    }

    // add new opam override

    // wait, on macOS sometimes it doesn't pick up changes
    await new Promise((resolve) => setTimeout(resolve, 1000));

    await FixtureUtils.initialize(path.join(p.opamRegistry.overridePath, 'packages'), [
      helpers.dir(
        'dep',
        helpers.packageJson({}),
        helpers.dir('files', helpers.file('hello', 'overridden')),
      ),
    ]);

    // drop local caches but not lock and see we still "locked" to an non
    // overridden package
    rimraf.sync(path.join(p.projectPath, '_esy'));
    await p.esy(`install`);
    await p.esy(`build`);

    {
      // Because of the way we split the args, on Windows, we need not quote esy command expressions
      let command =
        process.platform == 'win32'
          ? `cat #{@opam/dep.lib}/hello`
          : `cat '#{@opam/dep.lib}/hello'`;

      const {stdout} = await p.esy(command);
      expect(stdout.trim()).toBe('not-overridden');
    }

    // drop local caches and lock and see we are picking up the overridden
    // package.
    rimraf.sync(path.join(p.projectPath, '_esy'));
    rimraf.sync(path.join(p.projectPath, 'esy.lock'));

    await p.esy(`install`);
    await p.esy(`build`);

    {
      // Because of the way we split the args, on Windows, we need not quote esy command expressions
      let command =
        process.platform == 'win32'
          ? `cat #{@opam/dep.lib}/hello`
          : `cat '#{@opam/dep.lib}/hello'`;

      const {stdout} = await p.esy(command);
      expect(stdout.trim()).toBe('overridden');
    }
  });

  test(`override updates should be picked up`, async () => {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      helpers.packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          dep: '*',
        },
        resolutions: {
          dep: 'path:dep',
        },
      }),
      helpers.dir(
        'dep',
        helpers.packageJson({
          name: 'dep',
          version: '0.0.0',
          esy: {
            build: 'true',
            install: 'cp ./hello #{self.lib}/hello',
          },
        }),
        helpers.file('hello', 'ok'),
      ),
    );

    await p.esy(`install`);
    await p.esy(`build`);

    // check what we have w/o override
    {
      // Because of the way we split the args, on Windows, we need not quote esy command expressions
      let command =
        process.platform == 'win32' ? `cat #{dep.lib}/hello` : `cat '#{dep.lib}/hello'`;

      const {stdout} = await p.esy(command);
      expect(stdout.trim()).toBe('ok');
    }

    // add new override

    // wait, on macOS sometimes it doesn't pick up changes
    await new Promise((resolve) => setTimeout(resolve, 1000));

    await FixtureUtils.initialize(p.projectPath, [
      helpers.packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          dep: '*',
        },
        resolutions: {
          dep: {
            source: 'path:dep',
            override: {
              install: 'cp ./hello #{self.lib}/hello2',
            },
          },
        },
      }),
    ]);

    await p.esy(`install`);
    await p.esy(`build`);

    {
      let command =
        process.platform == 'win32' ? `cat #{dep.lib}/hello2` : `cat '#{dep.lib}/hello2'`;

      const {stdout} = await p.esy(command);
      expect(stdout.trim()).toBe('ok');
    }
  });

  it(`invalidates sandbox cache on 'esy' invocation`, async () => {
    const p = await helpers.createTestSandbox();
    await p.fixture(
      helpers.packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          dep: '^1.0.0',
        },
      }),
    );
    await p.defineNpmPackage({
      name: 'dep',
      version: '2.0.0',
    });

    await expect(p.esy('')).rejects.toThrow();

    // wait, on macOS sometimes it doesn't pick up changes
    await new Promise((resolve) => setTimeout(resolve, 1000));

    await FixtureUtils.initialize(p.projectPath, [
      helpers.packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          dep: '^2.0.0',
        },
      }),
    ]);

    await p.esy('');
  });
});
