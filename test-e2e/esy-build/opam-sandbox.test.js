// @flow

const helpers = require('../test/helpers.js');

describe('build opam sandbox', () => {
  it('builds an opam sandbox with a single opam file', async () => {
    const p = await helpers.createTestSandbox();

    await p.defineNpmPackage({
      name: '@esy-ocaml/substs',
      version: '0.0.0',
      esy: {},
    });

    await p.fixture(
      helpers.file(
        'opam',
        `
        opam-version: "1.2"
        build: [
          ${helpers.buildCommandInOpam('hello.js')}
          ["cp" "hello.cmd" "%{bin}%/hello.cmd"]
          ["cp" "hello.js" "%{bin}%/hello.js"]
        ]
      `,
      ),
      helpers.dummyExecutable('hello'),
    );

    await p.esy('install --skip-repository-update');
    await p.esy('build');

    {
      const {stdout} = await p.esy('x hello.cmd');
      expect(stdout.trim()).toEqual('__hello__');
    }
  });

  it('builds an opam sandbox with multiple opam files', async () => {
    const p = await helpers.createTestSandbox(
      helpers.file(
        'one.opam',
        `
        opam-version: "1.2"
        build: [
          ["true"]
        ]
        install: [
          ["true"]
        ]
      `,
      ),
      helpers.file(
        'two.opam',
        `
        opam-version: "1.2"
        build: [
          ["true"]
        ]
        install: [
          ["true"]
        ]
      `,
      ),
    );

    await p.defineNpmPackage({
      name: '@esy-ocaml/substs',
      version: '0.0.0',
      esy: {},
    });

    await p.esy('install');
    await p.esy('build');
  });

  it('variables stress test', async () => {
    const p = await helpers.createTestSandbox(
      helpers.file(
        'root.opam',
        `
        opam-version: "1.2"
        version: "in-dev"
        depends: ["dep"]
        build: [
          ["prefix" prefix]
          ["lib" lib]
          ["libexec" libexec]
          ["bin" bin]
          ["sbin" sbin]
          ["share" share]
          ["doc" doc]
          ["etc" etc]
          ["man" man]
          ["toplevel" toplevel]
          ["stublibs" stublibs]
          ["name" name]
          ["version" version]
          ["opam-version" opam-version]
          ["root" root]
          ["jobs" jobs]
          ["make" make]
          ["arch" arch]
          ["os" os]
          ["os-distribution" os-distribution]
          ["os-family" os-family]
          ["os-version" os-version]

          ["_:name" _:name]
          ["_:version" _:version]
          ["_:depends" _:depends]
          ["_:installed" _:installed]
          ["_:enable" _:enable]
          ["_:pinned" _:pinned]
          ["_:bin" _:bin]
          ["_:sbin" _:sbin]
          ["_:lib" _:lib]
          ["_:lib_root" _:lib_root]
          ["_:libexec" _:libexec]
          ["_:libexec_root" _:libexec_root]
          ["_:man" _:man]
          ["_:doc" _:doc]
          ["_:share" _:share]
          ["_:share_root" _:share_root]
          ["_:etc" _:etc]
          ["_:toplevel" _:toplevel]
          ["_:stublibs" _:stublibs]
          ["_:build" _:build]
          ["_:hash" _:hash]
          ["_:dev" _:dev]
          ["_:build-id" _:build-id]

          ["root:name" root:name]
          ["root:version" root:version]
          ["root:depends" root:depends]
          ["root:installed" root:installed]
          ["root:enable" root:enable]
          ["root:pinned" root:pinned]
          ["root:bin" root:bin]
          ["root:sbin" root:sbin]
          ["root:lib" root:lib]
          ["root:lib_root" root:lib_root]
          ["root:libexec" root:libexec]
          ["root:libexec_root" root:libexec_root]
          ["root:man" root:man]
          ["root:doc" root:doc]
          ["root:share" root:share]
          ["root:share_root" root:share_root]
          ["root:etc" root:etc]
          ["root:toplevel" root:toplevel]
          ["root:stublibs" root:stublibs]
          ["root:build" root:build]
          ["root:hash" root:hash]
          ["root:dev" root:dev]
          ["root:build-id" root:build-id]

          ["dep:name" dep:name]
          ["dep:version" dep:version]
          ["dep:depends" dep:depends]
          ["dep:installed" dep:installed]
          ["dep:enable" dep:enable]
          ["dep:pinned" dep:pinned]
          ["dep:bin" dep:bin]
          ["dep:sbin" dep:sbin]
          ["dep:lib" dep:lib]
          ["dep:lib_root" dep:lib_root]
          ["dep:libexec" dep:libexec]
          ["dep:libexec_root" dep:libexec_root]
          ["dep:man" dep:man]
          ["dep:doc" dep:doc]
          ["dep:share" dep:share]
          ["dep:share_root" dep:share_root]
          ["dep:etc" dep:etc]
          ["dep:toplevel" dep:toplevel]
          ["dep:stublibs" dep:stublibs]
          ["dep:build" dep:build]
          ["dep:hash" dep:hash]
          ["dep:dev" dep:dev]
          ["dep:build-id" dep:build-id]
        ]
        install: [
          ["prefix" prefix]
          ["lib" lib]
          ["libexec" libexec]
          ["bin" bin]
          ["sbin" sbin]
          ["share" share]
          ["doc" doc]
          ["etc" etc]
          ["man" man]
          ["toplevel" toplevel]
          ["stublibs" stublibs]
          ["name" name]
          ["version" version]
          ["opam-version" opam-version]
          ["root" root]
          ["jobs" jobs]
          ["make" make]
          ["arch" arch]
          ["os" os]
          ["os-distribution" os-distribution]
          ["os-family" os-family]
          ["os-version" os-version]

          ["_:name" _:name]
          ["_:version" _:version]
          ["_:depends" _:depends]
          ["_:installed" _:installed]
          ["_:enable" _:enable]
          ["_:pinned" _:pinned]
          ["_:bin" _:bin]
          ["_:sbin" _:sbin]
          ["_:lib" _:lib]
          ["_:lib_root" _:lib_root]
          ["_:libexec" _:libexec]
          ["_:libexec_root" _:libexec_root]
          ["_:man" _:man]
          ["_:doc" _:doc]
          ["_:share" _:share]
          ["_:share_root" _:share_root]
          ["_:etc" _:etc]
          ["_:toplevel" _:toplevel]
          ["_:stublibs" _:stublibs]
          ["_:build" _:build]
          ["_:hash" _:hash]
          ["_:dev" _:dev]
          ["_:build-id" _:build-id]

          ["root:name" root:name]
          ["root:version" root:version]
          ["root:depends" root:depends]
          ["root:installed" root:installed]
          ["root:enable" root:enable]
          ["root:pinned" root:pinned]
          ["root:bin" root:bin]
          ["root:sbin" root:sbin]
          ["root:lib" root:lib]
          ["root:lib_root" root:lib_root]
          ["root:libexec" root:libexec]
          ["root:libexec_root" root:libexec_root]
          ["root:man" root:man]
          ["root:doc" root:doc]
          ["root:share" root:share]
          ["root:share_root" root:share_root]
          ["root:etc" root:etc]
          ["root:toplevel" root:toplevel]
          ["root:stublibs" root:stublibs]
          ["root:build" root:build]
          ["root:hash" root:hash]
          ["root:dev" root:dev]
          ["root:build-id" root:build-id]

          ["dep:name" dep:name]
          ["dep:version" dep:version]
          ["dep:depends" dep:depends]
          ["dep:installed" dep:installed]
          ["dep:enable" dep:enable]
          ["dep:pinned" dep:pinned]
          ["dep:bin" dep:bin]
          ["dep:sbin" dep:sbin]
          ["dep:lib" dep:lib]
          ["dep:lib_root" dep:lib_root]
          ["dep:libexec" dep:libexec]
          ["dep:libexec_root" dep:libexec_root]
          ["dep:man" dep:man]
          ["dep:doc" dep:doc]
          ["dep:share" dep:share]
          ["dep:share_root" dep:share_root]
          ["dep:etc" dep:etc]
          ["dep:toplevel" dep:toplevel]
          ["dep:stublibs" dep:stublibs]
          ["dep:build" dep:build]
          ["dep:hash" dep:hash]
          ["dep:dev" dep:dev]
          ["dep:build-id" dep:build-id]
        ]
      `,
      ),
    );

    await p.defineNpmPackage({
      name: '@esy-ocaml/substs',
      version: '0.0.0',
      esy: {},
    });

    await p.defineOpamPackage({
      name: 'dep',
      version: '1.0.0',
      opam: `
        opam-version: "1.2"
      `,
      url: null,
    });

    await p.esy('install --skip-repository-update');
    const {stdout} = await p.esy('build-plan');
    const plan = JSON.parse(stdout);

    const {stdout: stdoutDep} = await p.esy('build-plan -p @opam/dep@opam:1.0.0');
    const depPlan = JSON.parse(stdoutDep);

    const expectBuild = [
      ['prefix', `%{localStore}%/s/${plan.id}`],
      ['lib', `%{localStore}%/s/${plan.id}/lib`],
      ['libexec', `%{localStore}%/s/${plan.id}/lib`],
      ['bin', `%{localStore}%/s/${plan.id}/bin`],
      ['sbin', `%{localStore}%/s/${plan.id}/sbin`],
      ['share', `%{localStore}%/s/${plan.id}/share`],
      ['doc', `%{localStore}%/s/${plan.id}/doc`],
      ['etc', `%{localStore}%/s/${plan.id}/etc`],
      ['man', `%{localStore}%/s/${plan.id}/man`],
      ['toplevel', `%{localStore}%/s/${plan.id}/toplevel`],
      ['stublibs', `%{localStore}%/s/${plan.id}/stublibs`],
      ['name', `root`],
      ['version', `in-dev`],
      ['opam-version', '2'],
      ['root', ''],
      ['jobs', '4'],
      ['make', 'make'],
      ['arch', expect.stringContaining('')],
      ['os', expect.stringContaining('')],
      ['os-distribution', expect.stringContaining('')],
      ['os-family', expect.stringContaining('')],
      ['os-version', expect.stringContaining('')],

      ['_:name', 'root'],
      ['_:version', 'in-dev'],
      ['_:depends', ''],
      ['_:installed', 'true'],
      ['_:enable', 'enable'],
      ['_:pinned', ''],
      ['_:bin', `%{localStore}%/s/${plan.id}/bin`],
      ['_:sbin', `%{localStore}%/s/${plan.id}/sbin`],
      ['_:lib', `%{localStore}%/s/${plan.id}/lib/root`],
      ['_:lib_root', `%{localStore}%/s/${plan.id}/lib`],
      ['_:libexec', `%{localStore}%/s/${plan.id}/lib/root`],
      ['_:libexec_root', `%{localStore}%/s/${plan.id}/lib`],
      ['_:man', `%{localStore}%/s/${plan.id}/man`],
      ['_:doc', `%{localStore}%/s/${plan.id}/doc/root`],
      ['_:share', `%{localStore}%/s/${plan.id}/share/root`],
      ['_:share_root', `%{localStore}%/s/${plan.id}/share`],
      ['_:etc', `%{localStore}%/s/${plan.id}/etc/root`],
      ['_:toplevel', `%{localStore}%/s/${plan.id}/toplevel`],
      ['_:stublibs', `%{localStore}%/s/${plan.id}/stublibs`],
      ['_:build', `%{localStore}%/b/${plan.id}`],
      ['_:hash', ''],
      ['_:dev', 'true'],
      ['_:build-id', plan.id],

      ['root:name', 'root'],
      ['root:version', 'in-dev'],
      ['root:depends', ''],
      ['root:installed', 'false'],
      ['root:enable', 'disable'],
      ['root:pinned', ''],
      ['root:bin', `%{localStore}%/s/${plan.id}/bin`],
      ['root:sbin', `%{localStore}%/s/${plan.id}/sbin`],
      ['root:lib', `%{localStore}%/s/${plan.id}/lib/root`],
      ['root:lib_root', `%{localStore}%/s/${plan.id}/lib`],
      ['root:libexec', `%{localStore}%/s/${plan.id}/lib/root`],
      ['root:libexec_root', `%{localStore}%/s/${plan.id}/lib`],
      ['root:man', `%{localStore}%/s/${plan.id}/man`],
      ['root:doc', `%{localStore}%/s/${plan.id}/doc/root`],
      ['root:share', `%{localStore}%/s/${plan.id}/share/root`],
      ['root:share_root', `%{localStore}%/s/${plan.id}/share`],
      ['root:etc', `%{localStore}%/s/${plan.id}/etc/root`],
      ['root:toplevel', `%{localStore}%/s/${plan.id}/toplevel`],
      ['root:stublibs', `%{localStore}%/s/${plan.id}/stublibs`],
      ['root:build', `%{localStore}%/b/${plan.id}`],
      ['root:hash', ''],
      ['root:dev', 'true'],
      ['root:build-id', plan.id],

      ['dep:name', 'dep'],
      ['dep:version', '1.0.0'],
      ['dep:depends', ''],
      ['dep:installed', 'true'],
      ['dep:enable', 'enable'],
      ['dep:pinned', ''],
      ['dep:bin', `%{store}%/i/${depPlan.id}/bin`],
      ['dep:sbin', `%{store}%/i/${depPlan.id}/sbin`],
      ['dep:lib', `%{store}%/i/${depPlan.id}/lib/dep`],
      ['dep:lib_root', `%{store}%/i/${depPlan.id}/lib`],
      ['dep:libexec', `%{store}%/i/${depPlan.id}/lib/dep`],
      ['dep:libexec_root', `%{store}%/i/${depPlan.id}/lib`],
      ['dep:man', `%{store}%/i/${depPlan.id}/man`],
      ['dep:doc', `%{store}%/i/${depPlan.id}/doc/dep`],
      ['dep:share', `%{store}%/i/${depPlan.id}/share/dep`],
      ['dep:share_root', `%{store}%/i/${depPlan.id}/share`],
      ['dep:etc', `%{store}%/i/${depPlan.id}/etc/dep`],
      ['dep:toplevel', `%{store}%/i/${depPlan.id}/toplevel`],
      ['dep:stublibs', `%{store}%/i/${depPlan.id}/stublibs`],
      ['dep:build', `%{globalStorePrefix}%/4/b/${depPlan.id}`],
      ['dep:hash', ''],
      ['dep:dev', 'false'],
      ['dep:build-id', depPlan.id],
    ];

    for (let i = 0; i < expectBuild.length; i++) {
      expect(plan.build[i]).toEqual(expectBuild[i]);
    }
    expect(plan.build.length).toBe(expectBuild.length);

    const expectInstall = [
      ['prefix', `%{localStore}%/s/${plan.id}`],
      ['lib', `%{localStore}%/s/${plan.id}/lib`],
      ['libexec', `%{localStore}%/s/${plan.id}/lib`],
      ['bin', `%{localStore}%/s/${plan.id}/bin`],
      ['sbin', `%{localStore}%/s/${plan.id}/sbin`],
      ['share', `%{localStore}%/s/${plan.id}/share`],
      ['doc', `%{localStore}%/s/${plan.id}/doc`],
      ['etc', `%{localStore}%/s/${plan.id}/etc`],
      ['man', `%{localStore}%/s/${plan.id}/man`],
      ['toplevel', `%{localStore}%/s/${plan.id}/toplevel`],
      ['stublibs', `%{localStore}%/s/${plan.id}/stublibs`],
      ['name', `root`],
      ['version', `in-dev`],
      ['opam-version', '2'],
      ['root', ''],
      ['jobs', '4'],
      ['make', 'make'],
      ['arch', expect.stringContaining('')],
      ['os', expect.stringContaining('')],
      ['os-distribution', expect.stringContaining('')],
      ['os-family', expect.stringContaining('')],
      ['os-version', expect.stringContaining('')],

      ['_:name', 'root'],
      ['_:version', 'in-dev'],
      ['_:depends', ''],
      ['_:installed', 'true'],
      ['_:enable', 'enable'],
      ['_:pinned', ''],
      ['_:bin', `%{localStore}%/s/${plan.id}/bin`],
      ['_:sbin', `%{localStore}%/s/${plan.id}/sbin`],
      ['_:lib', `%{localStore}%/s/${plan.id}/lib/root`],
      ['_:lib_root', `%{localStore}%/s/${plan.id}/lib`],
      ['_:libexec', `%{localStore}%/s/${plan.id}/lib/root`],
      ['_:libexec_root', `%{localStore}%/s/${plan.id}/lib`],
      ['_:man', `%{localStore}%/s/${plan.id}/man`],
      ['_:doc', `%{localStore}%/s/${plan.id}/doc/root`],
      ['_:share', `%{localStore}%/s/${plan.id}/share/root`],
      ['_:share_root', `%{localStore}%/s/${plan.id}/share`],
      ['_:etc', `%{localStore}%/s/${plan.id}/etc/root`],
      ['_:toplevel', `%{localStore}%/s/${plan.id}/toplevel`],
      ['_:stublibs', `%{localStore}%/s/${plan.id}/stublibs`],
      ['_:build', `%{localStore}%/b/${plan.id}`],
      ['_:hash', ''],
      ['_:dev', 'true'],
      ['_:build-id', plan.id],

      ['root:name', 'root'],
      ['root:version', 'in-dev'],
      ['root:depends', ''],
      ['root:installed', 'false'],
      ['root:enable', 'disable'],
      ['root:pinned', ''],
      ['root:bin', `%{localStore}%/s/${plan.id}/bin`],
      ['root:sbin', `%{localStore}%/s/${plan.id}/sbin`],
      ['root:lib', `%{localStore}%/s/${plan.id}/lib/root`],
      ['root:lib_root', `%{localStore}%/s/${plan.id}/lib`],
      ['root:libexec', `%{localStore}%/s/${plan.id}/lib/root`],
      ['root:libexec_root', `%{localStore}%/s/${plan.id}/lib`],
      ['root:man', `%{localStore}%/s/${plan.id}/man`],
      ['root:doc', `%{localStore}%/s/${plan.id}/doc/root`],
      ['root:share', `%{localStore}%/s/${plan.id}/share/root`],
      ['root:share_root', `%{localStore}%/s/${plan.id}/share`],
      ['root:etc', `%{localStore}%/s/${plan.id}/etc/root`],
      ['root:toplevel', `%{localStore}%/s/${plan.id}/toplevel`],
      ['root:stublibs', `%{localStore}%/s/${plan.id}/stublibs`],
      ['root:build', `%{localStore}%/b/${plan.id}`],
      ['root:hash', ''],
      ['root:dev', 'true'],
      ['root:build-id', plan.id],

      ['dep:name', 'dep'],
      ['dep:version', '1.0.0'],
      ['dep:depends', ''],
      ['dep:installed', 'true'],
      ['dep:enable', 'enable'],
      ['dep:pinned', ''],
      ['dep:bin', `%{store}%/i/${depPlan.id}/bin`],
      ['dep:sbin', `%{store}%/i/${depPlan.id}/sbin`],
      ['dep:lib', `%{store}%/i/${depPlan.id}/lib/dep`],
      ['dep:lib_root', `%{store}%/i/${depPlan.id}/lib`],
      ['dep:libexec', `%{store}%/i/${depPlan.id}/lib/dep`],
      ['dep:libexec_root', `%{store}%/i/${depPlan.id}/lib`],
      ['dep:man', `%{store}%/i/${depPlan.id}/man`],
      ['dep:doc', `%{store}%/i/${depPlan.id}/doc/dep`],
      ['dep:share', `%{store}%/i/${depPlan.id}/share/dep`],
      ['dep:share_root', `%{store}%/i/${depPlan.id}/share`],
      ['dep:etc', `%{store}%/i/${depPlan.id}/etc/dep`],
      ['dep:toplevel', `%{store}%/i/${depPlan.id}/toplevel`],
      ['dep:stublibs', `%{store}%/i/${depPlan.id}/stublibs`],
      ['dep:build', `%{globalStorePrefix}%/4/b/${depPlan.id}`],
      ['dep:hash', ''],
      ['dep:dev', 'false'],
      ['dep:build-id', depPlan.id],
    ];

    for (let i = 0; i < expectInstall.length; i++) {
      expect(plan.install[i]).toEqual(expectInstall[i]);
    }
    expect(plan.install.length).toBe(expectInstall.length);
  });
});
