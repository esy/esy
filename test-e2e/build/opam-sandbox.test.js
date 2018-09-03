// @flow

const {
  file,
  dir,
  packageJson,
  createTestSandbox,
  promiseExec,
  ocamlPackage,
  skipSuiteOnWindows,
} = require('../test/helpers.js');

skipSuiteOnWindows();

describe('build opam sandbox', () => {
  it('builds an opam sandbox with a single opam file', async () => {
    const p = await createTestSandbox(
      file(
        'opam',
        `
        opam-version: "1.2"
        build: [
          ["ocamlopt" "-o" "%{bin}%/hello" "hello.ml"]
        ]
      `,
      ),
      file('hello.ml', 'let () = print_endline "__hello__"'),
      dir(
        'node_modules',
        ocamlPackage(),
        dir(
          '@esy-ocaml',
          dir(
            'substs',
            packageJson({
              name: '@esy-ocaml/substs',
              version: '0.0.0',
            }),
          ),
        ),
      ),
    );

    await p.esy('build');
    expect((await p.esy('x hello')).stdout).toEqual(expect.stringContaining('__hello__'));
  });

  it('builds an opam sandbox with multiple opam files', async () => {
    const p = await createTestSandbox(
      file(
        'one.opam',
        `
        opam-version: "1.2"
        build: [
          ["false"]
        ]
        install: [
          ["true"]
        ]
      `,
      ),
      file(
        'two.opam',
        `
        opam-version: "1.2"
        build: [
          ["false"]
        ]
        install: [
          ["true"]
        ]
      `,
      ),
      dir(
        'node_modules',
        ocamlPackage(),
        dir(
          '@esy-ocaml',
          dir(
            'substs',
            packageJson({
              name: '@esy-ocaml/substs',
              version: '0.0.0',
            }),
          ),
        ),
      ),
    );

    await p.esy('build');
    await p.esy('build which ocamlopt');
  });

  it('variables stress test', async () => {
    const p = await createTestSandbox(
      file(
        'opam',
        `
        opam-version: "1.2"
        depends: ["dep"]
        build: [
          ["global-prefix" prefix]
          ["global-lib" lib]
          ["global-libexec" libexec]
          ["global-bin" bin]
          ["global-sbin" sbin]
          ["global-share" share]
          ["global-doc" doc]
          ["global-etc" etc]
          ["global-man" man]
          ["global-toplevel" toplevel]
          ["global-stublibs" stublibs]
          ["global-name" name]
          ["global-version" version]
          ["global-opam-version" opam-version]
          ["global-root" root]
          ["global-jobs" jobs]
          ["global-make" make]
          ["global-arch" arch]
          ["global-os" os]
          ["global-os-distribution" os-distribution]
          ["global-os-family" os-family]
          ["global-os-version" os-version]

          ["self-name" _:name]
          ["self-version" _:version]
          ["self-depends" _:depends]
          ["self-installed" _:installed]
          ["self-enable" _:enable]
          ["self-pinned" _:pinned]
          ["self-bin" _:bin]
          ["self-sbin" _:sbin]
          ["self-lib" _:lib]
          ["self-lib_root" _:lib_root]
          ["self-libexec" _:libexec]
          ["self-libexec_root" _:libexec_root]
          ["self-man" _:man]
          ["self-doc" _:doc]
          ["self-share" _:share]
          ["self-share_root" _:share_root]
          ["self-etc" _:etc]
          ["self-toplevel" _:toplevel]
          ["self-stublibs" _:stublibs]
          ["self-build" _:build]
          ["self-hash" _:hash]
          ["self-dev" _:dev]
          ["self-build-id" _:build-id]

          ["scoped-name" root:name]
          ["scoped-version" root:version]
          ["scoped-depends" root:depends]
          ["scoped-installed" root:installed]
          ["scoped-enable" root:enable]
          ["scoped-pinned" root:pinned]
          ["scoped-bin" root:bin]
          ["scoped-sbin" root:sbin]
          ["scoped-lib" root:lib]
          ["scoped-lib_root" root:lib_root]
          ["scoped-libexec" root:libexec]
          ["scoped-libexec_root" root:libexec_root]
          ["scoped-man" root:man]
          ["scoped-doc" root:doc]
          ["scoped-share" root:share]
          ["scoped-share_root" root:share_root]
          ["scoped-etc" root:etc]
          ["scoped-toplevel" root:toplevel]
          ["scoped-stublibs" root:stublibs]
          ["scoped-build" root:build]
          ["scoped-hash" root:hash]
          ["scoped-dev" root:dev]
          ["scoped-build-id" root:build-id]

          ["dep-name" dep:name]
          ["dep-version" dep:version]
          ["dep-depends" dep:depends]
          ["dep-installed" dep:installed]
          ["dep-enable" dep:enable]
          ["dep-pinned" dep:pinned]
          ["dep-bin" dep:bin]
          ["dep-sbin" dep:sbin]
          ["dep-lib" dep:lib]
          ["dep-lib_root" dep:lib_root]
          ["dep-libexec" dep:libexec]
          ["dep-libexec_root" dep:libexec_root]
          ["dep-man" dep:man]
          ["dep-doc" dep:doc]
          ["dep-share" dep:share]
          ["dep-share_root" dep:share_root]
          ["dep-etc" dep:etc]
          ["dep-toplevel" dep:toplevel]
          ["dep-stublibs" dep:stublibs]
          ["dep-build" dep:build]
          ["dep-hash" dep:hash]
          ["dep-dev" dep:dev]
          ["dep-build-id" dep:build-id]
        ]
        install: [
          ["global-prefix" prefix]
          ["global-lib" lib]
          ["global-libexec" libexec]
          ["global-bin" bin]
          ["global-sbin" sbin]
          ["global-share" share]
          ["global-doc" doc]
          ["global-etc" etc]
          ["global-man" man]
          ["global-toplevel" toplevel]
          ["global-stublibs" stublibs]
          ["global-name" name]
          ["global-version" version]
          ["global-opam-version" opam-version]
          ["global-root" root]
          ["global-jobs" jobs]
          ["global-make" make]
          ["global-arch" arch]
          ["global-os" os]
          ["global-os-distribution" os-distribution]
          ["global-os-family" os-family]
          ["global-os-version" os-version]

          ["self-name" _:name]
          ["self-version" _:version]
          ["self-depends" _:depends]
          ["self-installed" _:installed]
          ["self-enable" _:enable]
          ["self-pinned" _:pinned]
          ["self-bin" _:bin]
          ["self-sbin" _:sbin]
          ["self-lib" _:lib]
          ["self-lib_root" _:lib_root]
          ["self-libexec" _:libexec]
          ["self-libexec_root" _:libexec_root]
          ["self-man" _:man]
          ["self-doc" _:doc]
          ["self-share" _:share]
          ["self-share_root" _:share_root]
          ["self-etc" _:etc]
          ["self-toplevel" _:toplevel]
          ["self-stublibs" _:stublibs]
          ["self-build" _:build]
          ["self-hash" _:hash]
          ["self-dev" _:dev]
          ["self-build-id" _:build-id]

          ["scoped-name" root:name]
          ["scoped-version" root:version]
          ["scoped-depends" root:depends]
          ["scoped-installed" root:installed]
          ["scoped-enable" root:enable]
          ["scoped-pinned" root:pinned]
          ["scoped-bin" root:bin]
          ["scoped-sbin" root:sbin]
          ["scoped-lib" root:lib]
          ["scoped-lib_root" root:lib_root]
          ["scoped-libexec" root:libexec]
          ["scoped-libexec_root" root:libexec_root]
          ["scoped-man" root:man]
          ["scoped-doc" root:doc]
          ["scoped-share" root:share]
          ["scoped-share_root" root:share_root]
          ["scoped-etc" root:etc]
          ["scoped-toplevel" root:toplevel]
          ["scoped-stublibs" root:stublibs]
          ["scoped-build" root:build]
          ["scoped-hash" root:hash]
          ["scoped-dev" root:dev]
          ["scoped-build-id" root:build-id]

          ["dep-name" dep:name]
          ["dep-version" dep:version]
          ["dep-depends" dep:depends]
          ["dep-installed" dep:installed]
          ["dep-enable" dep:enable]
          ["dep-pinned" dep:pinned]
          ["dep-bin" dep:bin]
          ["dep-sbin" dep:sbin]
          ["dep-lib" dep:lib]
          ["dep-lib_root" dep:lib_root]
          ["dep-libexec" dep:libexec]
          ["dep-libexec_root" dep:libexec_root]
          ["dep-man" dep:man]
          ["dep-doc" dep:doc]
          ["dep-share" dep:share]
          ["dep-share_root" dep:share_root]
          ["dep-etc" dep:etc]
          ["dep-toplevel" dep:toplevel]
          ["dep-stublibs" dep:stublibs]
          ["dep-build" dep:build]
          ["dep-hash" dep:hash]
          ["dep-dev" dep:dev]
          ["dep-build-id" dep:build-id]
        ]
      `,
      ),
      dir(
        'node_modules',
        ocamlPackage(),
        dir(
          '@esy-ocaml',
          dir(
            'substs',
            packageJson({
              name: '@esy-ocaml/substs',
              version: '0.0.0',
            }),
          ),
        ),
        dir(
          '@opam',
          dir(
            'dep',
            dir(
              '_esy',
              file(
                'opam',
                `
                opam-version: "1.2"
                version: "1.0.0"
                name: "dep"
                `,
              ),
            ),
          ),
        ),
      ),
    );

    const {stdout} = await p.esy('build-plan');
    const plan = JSON.parse(stdout);

    const {stdout: stdoutDep} = await p.esy('build-plan ./node_modules/@opam/dep');
    const depPlan = JSON.parse(stdoutDep);

    expect(plan.build).toEqual([
      ['global-prefix', `%{localStore}%/s/${plan.id}`],
      ['global-lib', `%{localStore}%/s/${plan.id}/lib`],
      ['global-libexec', `%{localStore}%/s/${plan.id}/lib`],
      ['global-bin', `%{localStore}%/s/${plan.id}/bin`],
      ['global-sbin', `%{localStore}%/s/${plan.id}/sbin`],
      ['global-share', `%{localStore}%/s/${plan.id}/share`],
      ['global-doc', `%{localStore}%/s/${plan.id}/doc`],
      ['global-etc', `%{localStore}%/s/${plan.id}/etc`],
      ['global-man', `%{localStore}%/s/${plan.id}/man`],
      ['global-toplevel', `%{localStore}%/s/${plan.id}/toplevel`],
      ['global-stublibs', `%{localStore}%/s/${plan.id}/stublibs`],
      ['global-name', `root`],
      ['global-version', `dev`],
      ['global-opam-version', '2'],
      ['global-root', ''],
      ['global-jobs', '4'],
      ['global-make', 'make'],
      ['global-arch', expect.stringContaining('')],
      ['global-os', expect.stringContaining('')],
      ['global-os-distribution', expect.stringContaining('')],
      ['global-os-family', expect.stringContaining('')],
      ['global-os-version', expect.stringContaining('')],

      ['self-name', 'root'],
      ['self-version', 'dev'],
      ['self-depends', ''],
      ['self-installed', 'true'],
      ['self-enable', 'enable'],
      ['self-pinned', ''],
      ['self-bin', `%{localStore}%/s/${plan.id}/bin`],
      ['self-sbin', `%{localStore}%/s/${plan.id}/sbin`],
      ['self-lib', `%{localStore}%/s/${plan.id}/lib/root`],
      ['self-lib_root', `%{localStore}%/s/${plan.id}/lib`],
      ['self-libexec', `%{localStore}%/s/${plan.id}/lib/root`],
      ['self-libexec_root', `%{localStore}%/s/${plan.id}/lib`],
      ['self-man', `%{localStore}%/s/${plan.id}/man`],
      ['self-doc', `%{localStore}%/s/${plan.id}/doc/root`],
      ['self-share', `%{localStore}%/s/${plan.id}/share/root`],
      ['self-share_root', `%{localStore}%/s/${plan.id}/share`],
      ['self-etc', `%{localStore}%/s/${plan.id}/etc/root`],
      ['self-toplevel', `%{localStore}%/s/${plan.id}/toplevel`],
      ['self-stublibs', `%{localStore}%/s/${plan.id}/stublibs`],
      ['self-build', `%{localStore}%/b/${plan.id}`],
      ['self-hash', ''],
      ['self-dev', 'true'],
      ['self-build-id', plan.id],

      ['scoped-name', 'root'],
      ['scoped-version', 'dev'],
      ['scoped-depends', ''],
      ['scoped-installed', 'false'],
      ['scoped-enable', 'disable'],
      ['scoped-pinned', ''],
      ['scoped-bin', `%{localStore}%/s/${plan.id}/bin`],
      ['scoped-sbin', `%{localStore}%/s/${plan.id}/sbin`],
      ['scoped-lib', `%{localStore}%/s/${plan.id}/lib/root`],
      ['scoped-lib_root', `%{localStore}%/s/${plan.id}/lib`],
      ['scoped-libexec', `%{localStore}%/s/${plan.id}/lib/root`],
      ['scoped-libexec_root', `%{localStore}%/s/${plan.id}/lib`],
      ['scoped-man', `%{localStore}%/s/${plan.id}/man`],
      ['scoped-doc', `%{localStore}%/s/${plan.id}/doc/root`],
      ['scoped-share', `%{localStore}%/s/${plan.id}/share/root`],
      ['scoped-share_root', `%{localStore}%/s/${plan.id}/share`],
      ['scoped-etc', `%{localStore}%/s/${plan.id}/etc/root`],
      ['scoped-toplevel', `%{localStore}%/s/${plan.id}/toplevel`],
      ['scoped-stublibs', `%{localStore}%/s/${plan.id}/stublibs`],
      ['scoped-build', `%{localStore}%/b/${plan.id}`],
      ['scoped-hash', ''],
      ['scoped-dev', 'true'],
      ['scoped-build-id', plan.id],

      ['dep-name', 'dep'],
      ['dep-version', '1.0.0'],
      ['dep-depends', ''],
      ['dep-installed', 'true'],
      ['dep-enable', 'enable'],
      ['dep-pinned', ''],
      ['dep-bin', `%{store}%/i/${depPlan.id}/bin`],
      ['dep-sbin', `%{store}%/i/${depPlan.id}/sbin`],
      ['dep-lib', `%{store}%/i/${depPlan.id}/lib/dep`],
      ['dep-lib_root', `%{store}%/i/${depPlan.id}/lib`],
      ['dep-libexec', `%{store}%/i/${depPlan.id}/lib/dep`],
      ['dep-libexec_root', `%{store}%/i/${depPlan.id}/lib`],
      ['dep-man', `%{store}%/i/${depPlan.id}/man`],
      ['dep-doc', `%{store}%/i/${depPlan.id}/doc/dep`],
      ['dep-share', `%{store}%/i/${depPlan.id}/share/dep`],
      ['dep-share_root', `%{store}%/i/${depPlan.id}/share`],
      ['dep-etc', `%{store}%/i/${depPlan.id}/etc/dep`],
      ['dep-toplevel', `%{store}%/i/${depPlan.id}/toplevel`],
      ['dep-stublibs', `%{store}%/i/${depPlan.id}/stublibs`],
      ['dep-build', `%{store}%/b/${depPlan.id}`],
      ['dep-hash', ''],
      ['dep-dev', 'false'],
      ['dep-build-id', depPlan.id],
    ]);

    expect(plan.install).toEqual([
      ['global-prefix', `%{localStore}%/s/${plan.id}`],
      ['global-lib', `%{localStore}%/s/${plan.id}/lib`],
      ['global-libexec', `%{localStore}%/s/${plan.id}/lib`],
      ['global-bin', `%{localStore}%/s/${plan.id}/bin`],
      ['global-sbin', `%{localStore}%/s/${plan.id}/sbin`],
      ['global-share', `%{localStore}%/s/${plan.id}/share`],
      ['global-doc', `%{localStore}%/s/${plan.id}/doc`],
      ['global-etc', `%{localStore}%/s/${plan.id}/etc`],
      ['global-man', `%{localStore}%/s/${plan.id}/man`],
      ['global-toplevel', `%{localStore}%/s/${plan.id}/toplevel`],
      ['global-stublibs', `%{localStore}%/s/${plan.id}/stublibs`],
      ['global-name', `root`],
      ['global-version', `dev`],
      ['global-opam-version', '2'],
      ['global-root', ''],
      ['global-jobs', '4'],
      ['global-make', 'make'],
      ['global-arch', expect.stringContaining('')],
      ['global-os', expect.stringContaining('')],
      ['global-os-distribution', expect.stringContaining('')],
      ['global-os-family', expect.stringContaining('')],
      ['global-os-version', expect.stringContaining('')],

      ['self-name', 'root'],
      ['self-version', 'dev'],
      ['self-depends', ''],
      ['self-installed', 'true'],
      ['self-enable', 'enable'],
      ['self-pinned', ''],
      ['self-bin', `%{localStore}%/s/${plan.id}/bin`],
      ['self-sbin', `%{localStore}%/s/${plan.id}/sbin`],
      ['self-lib', `%{localStore}%/s/${plan.id}/lib/root`],
      ['self-lib_root', `%{localStore}%/s/${plan.id}/lib`],
      ['self-libexec', `%{localStore}%/s/${plan.id}/lib/root`],
      ['self-libexec_root', `%{localStore}%/s/${plan.id}/lib`],
      ['self-man', `%{localStore}%/s/${plan.id}/man`],
      ['self-doc', `%{localStore}%/s/${plan.id}/doc/root`],
      ['self-share', `%{localStore}%/s/${plan.id}/share/root`],
      ['self-share_root', `%{localStore}%/s/${plan.id}/share`],
      ['self-etc', `%{localStore}%/s/${plan.id}/etc/root`],
      ['self-toplevel', `%{localStore}%/s/${plan.id}/toplevel`],
      ['self-stublibs', `%{localStore}%/s/${plan.id}/stublibs`],
      ['self-build', `%{localStore}%/b/${plan.id}`],
      ['self-hash', ''],
      ['self-dev', 'true'],
      ['self-build-id', plan.id],

      ['scoped-name', 'root'],
      ['scoped-version', 'dev'],
      ['scoped-depends', ''],
      ['scoped-installed', 'false'],
      ['scoped-enable', 'disable'],
      ['scoped-pinned', ''],
      ['scoped-bin', `%{localStore}%/s/${plan.id}/bin`],
      ['scoped-sbin', `%{localStore}%/s/${plan.id}/sbin`],
      ['scoped-lib', `%{localStore}%/s/${plan.id}/lib/root`],
      ['scoped-lib_root', `%{localStore}%/s/${plan.id}/lib`],
      ['scoped-libexec', `%{localStore}%/s/${plan.id}/lib/root`],
      ['scoped-libexec_root', `%{localStore}%/s/${plan.id}/lib`],
      ['scoped-man', `%{localStore}%/s/${plan.id}/man`],
      ['scoped-doc', `%{localStore}%/s/${plan.id}/doc/root`],
      ['scoped-share', `%{localStore}%/s/${plan.id}/share/root`],
      ['scoped-share_root', `%{localStore}%/s/${plan.id}/share`],
      ['scoped-etc', `%{localStore}%/s/${plan.id}/etc/root`],
      ['scoped-toplevel', `%{localStore}%/s/${plan.id}/toplevel`],
      ['scoped-stublibs', `%{localStore}%/s/${plan.id}/stublibs`],
      ['scoped-build', `%{localStore}%/b/${plan.id}`],
      ['scoped-hash', ''],
      ['scoped-dev', 'true'],
      ['scoped-build-id', plan.id],

      ['dep-name', 'dep'],
      ['dep-version', '1.0.0'],
      ['dep-depends', ''],
      ['dep-installed', 'true'],
      ['dep-enable', 'enable'],
      ['dep-pinned', ''],
      ['dep-bin', `%{store}%/i/${depPlan.id}/bin`],
      ['dep-sbin', `%{store}%/i/${depPlan.id}/sbin`],
      ['dep-lib', `%{store}%/i/${depPlan.id}/lib/dep`],
      ['dep-lib_root', `%{store}%/i/${depPlan.id}/lib`],
      ['dep-libexec', `%{store}%/i/${depPlan.id}/lib/dep`],
      ['dep-libexec_root', `%{store}%/i/${depPlan.id}/lib`],
      ['dep-man', `%{store}%/i/${depPlan.id}/man`],
      ['dep-doc', `%{store}%/i/${depPlan.id}/doc/dep`],
      ['dep-share', `%{store}%/i/${depPlan.id}/share/dep`],
      ['dep-share_root', `%{store}%/i/${depPlan.id}/share`],
      ['dep-etc', `%{store}%/i/${depPlan.id}/etc/dep`],
      ['dep-toplevel', `%{store}%/i/${depPlan.id}/toplevel`],
      ['dep-stublibs', `%{store}%/i/${depPlan.id}/stublibs`],
      ['dep-build', `%{store}%/b/${depPlan.id}`],
      ['dep-hash', ''],
      ['dep-dev', 'false'],
      ['dep-build-id', depPlan.id],
    ]);
  });
});
