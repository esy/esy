// @flow

const outdent = require('outdent');
const helpers = require('../test/helpers.js');
const path = require('path');
const fs = require('../test/fs.js');
const FixtureUtils = require('../test/FixtureUtils.js');

helpers.skipSuiteOnWindows();

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
      const {stdout} = await p.esy(`cat '#{@opam/dep.lib}/hello'`);
      expect(stdout.trim()).toBe('not-overridden');
    }

    // add new opam override

    // wait, on macOS sometimes it doesn't pick up changes
    await new Promise(resolve => setTimeout(resolve, 1000));

    await FixtureUtils.initialize(path.join(p.opamRegistry.overridePath, 'packages'), [
      helpers.dir(
        'dep',
        helpers.packageJson({}),
        helpers.dir('files', helpers.file('hello', 'overridden')),
      ),
    ]);

    // drop local caches but not lock and see we still "locked" to an non
    // overridden package
    await p.run(`rm -rf ./_esy`);
    await p.esy(`install`);
    await p.esy(`build`);

    {
      const {stdout} = await p.esy(`cat '#{@opam/dep.lib}/hello'`);
      expect(stdout.trim()).toBe('not-overridden');
    }

    // drop local caches and lock and see we are picking up the overridden
    // package.
    await p.run(`rm -rf ./_esy`);
    await p.run(`rm -rf ./esy.lock`);

    await p.esy(`install`);
    await p.esy(`build`);

    {
      const {stdout} = await p.esy(`cat '#{@opam/dep.lib}/hello'`);
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
      const {stdout} = await p.esy(`cat '#{dep.lib}/hello'`);
      expect(stdout.trim()).toBe('ok');
    }

    // add new override

    // wait, on macOS sometimes it doesn't pick up changes
    await new Promise(resolve => setTimeout(resolve, 1000));

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
      const {stdout} = await p.esy(`cat '#{dep.lib}/hello2'`);
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
    await new Promise(resolve => setTimeout(resolve, 1000));

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
