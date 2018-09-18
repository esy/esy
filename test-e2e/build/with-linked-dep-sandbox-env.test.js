// @flow

const path = require('path');
const fs = require('fs');

const outdent = require('outdent');
const {
  createTestSandbox,
  ocamlPackage,
  packageJson,
  symlink,
  file,
  dir,
  skipSuiteOnWindows,
} = require('../test/helpers');

skipSuiteOnWindows('Needs investigation');

function makeFixture(p) {
  return [
    packageJson({
      name: 'with-linked-dep-sandbox-env',
      version: '1.0.0',
      esy: {
        build: 'true',
        sandboxEnv: {
          SANDBOX_ENV_VAR: 'global-sandbox-env-var',
        },
      },
      dependencies: {
        dep: '*',
      },
      buildTimeDependencies: {
        dep2: '*',
      },
      devDependencies: {
        dep3: '*',
      },
    }),
    dir(
      'node_modules',
      dir(
        'dep',
        symlink('package.json', path.join('..', '..', 'dep')),
        file(
          '_esylink',
          JSON.stringify({source: `link:${path.join(p.projectPath, 'dep')}`}),
        ),
      ),
      dir(
        'dep2',
        symlink('package.json', path.join('..', '..', 'dep2')),
        file(
          '_esylink',
          JSON.stringify({source: `link:${path.join(p.projectPath, 'dep2')}`}),
        ),
      ),
      dir(
        'dep3',
        symlink('package.json', path.join('..', '..', 'dep3')),
        file(
          '_esylink',
          JSON.stringify({source: `link:${path.join(p.projectPath, 'dep3')}`}),
        ),
      ),
      ocamlPackage(),
    ),
    dir(
      'dep',
      packageJson({
        name: 'dep',
        version: '1.0.0',
        esy: {
          build: [
            'cp #{self.root / self.name}.ml #{self.target_dir / self.name}.ml',
            'ocamlopt -o #{self.target_dir / self.name} #{self.target_dir / self.name}.ml',
          ],
          install: 'cp #{self.target_dir / self.name} #{self.bin / self.name}',
        },
        dependencies: {
          ocaml: '*',
        },
      }),
      file(
        'dep.ml',
        outdent`
      let () =
        let v = Sys.getenv "SANDBOX_ENV_VAR" in
        print_endline (v ^ "-in-dep");
    `,
      ),
    ),
    dir(
      'dep2',
      packageJson({
        name: 'dep2',
        version: '1.0.0',
        esy: {
          build: [
            'cp #{self.root / self.name}.ml #{self.target_dir / self.name}.ml',
            'ocamlopt -o #{self.target_dir / self.name} #{self.target_dir / self.name}.ml',
          ],
          install: 'cp #{self.target_dir / self.name} #{self.bin / self.name}',
        },
        dependencies: {
          ocaml: '*',
        },
      }),
      file(
        'dep2.ml',
        outdent`
      let () =
        let v = Sys.getenv "SANDBOX_ENV_VAR" in
        print_endline (v ^ "-in-dep2");
    `,
      ),
    ),
    dir(
      'dep3',
      packageJson({
        name: 'dep3',
        version: '1.0.0',
        license: 'MIT',
        esy: {
          build: [
            'cp #{self.root / self.name}.ml #{self.target_dir / self.name}.ml',
            'ocamlopt -o #{self.target_dir / self.name} #{self.target_dir / self.name}.ml',
          ],
          install: 'cp #{self.target_dir / self.name} #{self.bin / self.name}',
        },
        dependencies: {
          ocaml: '*',
        },
      }),
      file(
        'dep3.ml',
        outdent`
      let () =
        let v = Sys.getenv "SANDBOX_ENV_VAR" in
        print_endline (v ^ "-in-dep3");
    `,
      ),
    ),
  ];
}

describe('Linked deps with presen', () => {
  let p;

  beforeEach(async () => {
    p = await createTestSandbox();
    await p.fixture(...makeFixture(p));
    await p.esy('build');
  });

  it("sandbox env should be visible in runtime dep's all envs", async () => {
    const expecting = expect.stringMatching('global-sandbox-env-var-in-dep');

    const dep = await p.esy('dep');
    expect(dep.stdout).toEqual(expecting);

    const b = await p.esy('b dep');
    expect(b.stdout).toEqual(expecting);

    const x = await p.esy('x dep');
    expect(x.stdout).toEqual(expecting);
  });

  it("sandbox env should not be available in build time dep's envs", async () => {
    const expecting = expect.stringMatching('-in-dep2');

    const dep = await p.esy('dep2');
    expect(dep.stdout).toEqual(expecting);

    const b = await p.esy('b dep2');
    expect(b.stdout).toEqual(expecting);
  });

  it("sandbox env should not be available in dev dep's envs", async () => {
    const dep = await p.esy('dep3');
    expect(dep.stdout).toEqual(expect.stringMatching('-in-dep3'));
  });
});
