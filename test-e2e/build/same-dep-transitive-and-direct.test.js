// @flow

const path = require('path');
const {
  createTestSandbox,
  packageJson,
  dir,
  file,
  ocamlPackage,
  exeExtension,
} = require('../test/helpers');

function makePackage(
  {
    name,
    dependencies = {},
    devDependencies = {},
    optDependencies = {},
    exportedEnv = {},
  }: {
    name: string,
    dependencies?: {[name: string]: string},
    devDependencies?: {[name: string]: string},
    optDependencies?: {[name: string]: string},
    exportedEnv?: {[name: string]: {val: string}},
  },
  ...items
) {
  return dir(
    name,
    packageJson({
      name: name,
      version: '1.0.0',
      license: 'MIT',
      esy: {
        buildsInSource: true,
        build: 'ocamlopt -o #{self.root / self.name}.exe #{self.root / self.name}.ml',
        install: `cp #{self.root / self.name}.exe #{self.bin / self.name}${exeExtension}`,
        exportedEnv,
      },
      dependencies,
      optDependencies,
      devDependencies,
      '_esy.source': 'path:.',
    }),
    file(`${name}.ml`, `let () = print_endline "__${name}__"`),
    ...items,
  );
}

const fixture = [
  packageJson({
    name: 'withDep',
    version: '1.0.0',
    esy: {
      build: 'true',
    },
    dependencies: {
      dep: '*',
      focus: '*',
    },
  }),
  dir(
    'node_modules',
    makePackage({
      name: 'dep',
      dependencies: {
        focus: '*',
        depOfDep: '*',
        ocaml: '*',
      },
    }),
    makePackage({
      name: 'depOfDep',
      dependencies: {
        ocaml: '*',
        focus: '*',
      },
    }),
    makePackage({
      name: 'focus',
      dependencies: {
        ocaml: '*',
      },
      exportedEnv: {direct__val: {val: '__focus__', scope: 'local'}},
    }),
    ocamlPackage(),
  ),
];

describe('dep exists as transitive and direct dep at once', () => {
  it('package focus should be visible in all envs', async () => {
    const p = await createTestSandbox(...fixture);
    await p.esy('build');

    const expecting = expect.stringMatching('__focus__');

    const dep = await p.esy('focus');
    expect(dep.stdout).toEqual(expecting);

    const b = await p.esy('b focus');
    expect(b.stdout).toEqual(expecting);

    const x = await p.esy('x focus');
    expect(x.stdout).toEqual(expecting);
  });

  it('package focus local exports should be available', async () => {
    const p = await createTestSandbox(...fixture);
    const env = JSON.parse((await p.esy('build-env --json')).stdout);
    expect(env.direct__val).toBe('__focus__');
  });
});
