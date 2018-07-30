// @flow

const path = require('path');
const outdent = require('outdent');
const fs = require('fs-extra');
const {genFixture, file, dir, packageJson, ocamlPackagePath, promiseExec, ESYCOMMAND, skipSuiteOnWindows} = require('../test/helpers');

skipSuiteOnWindows('Needs investigation');

const fixture = [
  dir('app',
    packageJson({
      "name": "app",
      "version": "1.0.0",
      "esy": {
        "build": [
          [
            "cp",
            "#{self.original_root /}app.ml",
            "#{self.target_dir /}app.ml"
          ],
          [
            "ocamlopt",
            "-o",
            "#{self.target_dir / self.name}.exe",
            "#{self.target_dir /}app.ml"
          ]
        ],
        "install": [
          "cp $cur__target_dir/$cur__name.exe $cur__bin/$cur__name"
        ]
      },
      "dependencies": {
        "dep": "link:../dep",
        "another-dep": "link:../another-dep",
        "ocaml": `link:${ocamlPackagePath}`,
      }
    }),
    file('app.ml', outdent`
      let () = print_endline "app"
    `)
  ),
  dir('dep',
    packageJson({
      "name": "dep",
      "version": "1.0.0",
      "esy": {
        "build": [
          [
            "cp",
            "#{self.original_root /}dep.ml",
            "#{self.target_dir /}dep.ml"
          ],
          [
            "ocamlopt",
            "-o",
            "#{self.target_dir / self.name}.exe",
            "#{self.target_dir /}dep.ml"
          ]
        ],
        "install": [
          "cp $cur__target_dir/$cur__name.exe $cur__bin/$cur__name"
        ]
      },
      "dependencies": {
        "ocaml": `link:${ocamlPackagePath}`,
      }
    }),
    file('dep.ml', outdent`
      let () = print_endline "HELLO"
    `)
  ),
  dir('another-dep',
    packageJson({
      "name": "another-dep",
      "version": "1.0.0",
      "license": "MIT",
      "esy": {
        "build": [
          [
            "cp",
            "#{self.original_root /}AnotherDep.ml",
            "#{self.target_dir /}AnotherDep.ml"
          ],
          [
            "ocamlopt",
            "-o",
            "#{self.target_dir / self.name}.exe",
            "#{self.target_dir /}AnotherDep.ml"
          ]
        ],
        "install": [
          "cp $cur__target_dir/$cur__name.exe $cur__bin/$cur__name"
        ]
      },
      "dependencies": {
        "ocaml": `link:${ocamlPackagePath}`,
      }
    }),
    file('AnotherDep.ml', outdent`
      let () = print_endline "HELLO"
    `)
  ),
];

describe('Common - symlink workflow', () => {
  let p;
  let appEsy;

  beforeAll(async () => {
    p = await genFixture(...fixture);

    appEsy = args =>
      promiseExec(`${ESYCOMMAND} ${args}`, {
        cwd: path.resolve(p.projectPath, 'app'),
        env: {...process.env, ESY__PREFIX: p.esyPrefixPath},
      });

    await appEsy('install');
    await appEsy('build');

  });

  it('works without changes', async () => {
    const dep = await appEsy('dep');
    expect(dep.stdout).toEqual('HELLO\n');
    const anotherDep = await appEsy('another-dep');
    expect(anotherDep.stdout).toEqual('HELLO\n');
  });

  it('works with modified dep sources', async () => {
    await fs.writeFile(
      path.join(p.projectPath, 'dep', 'dep.ml'),
      'print_endline "HELLO_MODIFIED"',
    );

    await appEsy('build');
    const dep = await appEsy('dep');
    expect(dep.stdout).toEqual('HELLO_MODIFIED\n');
  });
});
