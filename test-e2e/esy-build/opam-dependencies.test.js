// @flow

const path = require('path');
const outdent = require('outdent');
const helpers = require('../test/helpers.js');
const FixtureUtils = require('../test/FixtureUtils.js');

describe('building @opam/* dependencies', () => {
  it('builds opam dependencies with patches', async () => {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      helpers.packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          '@opam/pkg': '*',
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
        name: 'pkg',
        version: '1.0.0',
        opam: outdent`
          opam-version: "2.0"
          patches: [
            "some.patch"
          ]
          build: [
            ${helpers.buildCommandInOpam('hello.js')}
            ["cp" "hello.cmd" "%{bin}%/hello.cmd"]
            ["cp" "hello.js" "%{bin}%/hello.js"]
          ]
        `,
      },
      [
        helpers.dummyExecutable('hello'),
        helpers.file(
          'some.patch',
          outdent`
            --- a/hello.js
            +++ b/hello.js
            @@ -1 +1 @@
            -console.log("__" + "hello" + "__");
            +console.log("__" + "hello-patched" + "__");

          `,
        ),
      ],
    );

    await p.esy('install');
    await p.esy('build');

    {
      const {stdout} = await p.esy('x hello.cmd');
      expect(stdout.trim()).toEqual('__hello-patched__');
    }
  });

  it('builds opam dependencies with patches (from overrides)', async () => {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      helpers.packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          '@opam/pkg': '*',
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
        name: 'pkg',
        version: '1.0.0',
        opam: outdent`
          opam-version: "2.0"
          patches: [
            "some.patch"
          ]
          build: [
            ${helpers.buildCommandInOpam('hello.js')}
            ["cp" "hello.cmd" "%{bin}%/hello.cmd"]
            ["cp" "hello.js" "%{bin}%/hello.js"]
          ]
        `,
      },
      [helpers.dummyExecutable('hello')],
    );

    await FixtureUtils.initialize(path.join(p.opamRegistry.overridePath, 'packages'), [
      helpers.dir(
        'pkg',
        helpers.packageJson({}),
        helpers.dir(
          'files',
          helpers.file(
            'some.patch',
            outdent`
            --- a/hello.js
            +++ b/hello.js
            @@ -1 +1 @@
            -console.log("__" + "hello" + "__");
            +console.log("__" + "hello-patched" + "__");

          `,
          ),
        ),
      ),
    ]);

    await p.esy('install');
    await p.esy('build');

    {
      const {stdout} = await p.esy('x hello.cmd');
      expect(stdout.trim()).toEqual('__hello-patched__');
    }
  });

  it('builds a project with an opam dep which refernces ocaml:* variables', async () => {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      helpers.packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          '@opam/pkg': '*',
        },
      }),
    );

    await p.defineNpmPackage({
      name: '@esy-ocaml/substs',
      version: '0.0.0',
      esy: {},
    });

    await p.defineNpmPackage({
      name: 'ocaml',
      version: '1.0.0',
      esy: {},
    });

    await p.defineOpamPackageOfFixture(
      {
        name: 'pkg',
        version: '1.0.0',
        opam: outdent`
          opam-version: "2.0"
          patches: [
            "false" {ocaml:version != "1.0.0"}
          ]
          depends: [
            "ocaml"
          ]
          build: [
            ${helpers.buildCommandInOpam('hello.js')}
            ["cp" "hello.cmd" "%{bin}%/hello.cmd"]
            ["cp" "hello.js" "%{bin}%/hello.js"]
          ]
        `,
      },
      [helpers.dummyExecutable('hello')],
    );

    await p.esy('install');
    await p.esy('build');

    {
      const {stdout} = await p.esy('x hello.cmd');
      expect(stdout.trim()).toEqual('__hello__');
    }
  });

  it('opam filter bug 1518', async () => {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      helpers.packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          '@opam/pkg': '*',
        },
      }),
    );

    await p.defineNpmPackage({
      name: '@esy-ocaml/substs',
      version: '0.0.0',
      esy: {},
    });

    await p.defineNpmPackage({
      name: 'ocaml',
      version: '5.1.1',
      esy: {},
    });

    await p.defineOpamPackageOfFixture(
      {
        name: 'pkg',
        version: '1.0.0',
        opam: outdent`
          opam-version: "2.0"
          depends: [
            "ocaml" {>= "4.04.1" & < "5.2.0" & != "5.1.0~alpha1"}
          ]
          build: [
            "true"
          ]
        `,
      },
      [helpers.dummyExecutable('hello')],
    );

    await p.esy('install');
    await p.esy('build');

    {
      await p.esy();
    }
  });

  it('builds opam dependencies with extra-sources', async () => {
    const p = await helpers.createTestSandbox();

    await p.fixture(
      helpers.packageJson({
        name: 'root',
        esy: {},
        dependencies: {
          '@opam/pkg': '*',
          '@opam/lib': '*',
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
        name: 'pkg',
        version: '1.0.0',
        opam: outdent`
          opam-version: "2.0"
          build: [
            ${helpers.buildCommandInOpam('hello.js')}
            ["cp" "hello.cmd" "%{bin}%/hello.cmd"]
            ["cp" "hello.js" "%{bin}%/hello.js"]
          ]
        `,
      },
      [helpers.dummyExecutable('hello')],
    );

    await p.defineOpamPackageOfExtraSource({
      name: 'lib',
      version: '1.0.0',
      opam: outdent`
          opam-version: "2.0"
        `,
    });

    await p.esy('install');
    await p.esy('build');

    {
      const {stdout} = await p.esy('x hello.cmd');
      expect(stdout.trim()).toEqual('__hello__');
    }
  });
});
