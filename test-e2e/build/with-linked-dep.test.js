// @flow

const path = require('path');
const fs = require('fs');
const {promisify} = require('util');
const open = promisify(fs.open);
const close = promisify(fs.close);

const {genFixture, packageJson, dir, file, symlink, ocamlPackage, exeExtension, skipSuiteOnWindows} = require('../test/helpers');

skipSuiteOnWindows();

const fixture = [
  packageJson({
    "name": "with-linked-dep",
    "version": "1.0.0",
    "license": "MIT",
    "esy": {
      "build": "true"
    },
    "dependencies": {
      "dep": "*"
    }
  }),
  dir('dep',
    packageJson({
      "name": "dep",
      "version": "1.0.0",
      "license": "MIT",
      "esy": {
        "build": [
          "cp #{self.root / self.name}.ml #{self.target_dir / self.name}.ml",
          "ocamlopt -o #{self.target_dir / self.name}.exe #{self.target_dir / self.name}.ml",
        ],
        "install": `cp #{self.target_dir / self.name}.exe #{self.bin / self.name}${exeExtension}`
      },
      "dependencies": {
        "ocaml": "*"
      }
    }),
    file('dep.ml', 'let () = print_endline "__dep__"'),
  ),
  dir('node_modules',
    dir('dep',
      file('_esylink', './dep'),
      symlink('package.json', '../../dep/package.json')
    ),
    ocamlPackage(),
  ),
];

describe('Build - with linked dep', () => {
  let p;

  beforeAll(async () => {
    p = await genFixture(...fixture);
    await p.esy('build');
  });

  it('package "dep" should be visible in all envs', async () => {
    const dep = await p.esy('dep');
    const b = await p.esy('b dep');
    const x = await p.esy('x dep');

    const expecting = expect.stringMatching('__dep__');

    expect(x.stdout).toEqual(expecting);
    expect(b.stdout).toEqual(expecting);
    expect(dep.stdout).toEqual(expecting);
  });

  it('should not rebuild dep with no changes', async done => {
    const noOpBuild = await p.esy('build');
    expect(noOpBuild.stdout).not.toEqual(
      expect.stringMatching('Building dep@1.0.0: starting'),
    );

    done();
  });

  it('should rebuild if file has been added', async () => {
    await open(path.join(p.projectPath, 'dep', 'dummy'), 'w').then(close);

    const rebuild = await p.esy('build');
    // TODO: why is this on stderr?
    expect(rebuild.stderr).toEqual(expect.stringMatching('Building dep@1.0.0: starting'));
  });
});
