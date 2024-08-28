---
id: esy-installer
title: esy-installer
authors: [prometheansacrifice]
---

OPAM packages follow a convention of emitting `.install` files so that
package managers can install the built
artifacts. [`opam-installer`](https://opam.ocaml.org/packages/opam-installer/)
is one such example. Thus, `esy` is responsible for reading `.install`
files and installing the built artifacts correctly. `esy-installer` is
an internal command, ie available only while creating esy recipes,
that can read `.install` files and install them in the sandbox.

By default, if a package creates one `.install` file, esy
automatically runs `esy-install` files internall. However, in some
customised setups, eg, [reason-native](https://github.com/reasonml/reason-native/blob/master/rely.json#L27), it's necessary to specify
how the built artifacts are installed.

Here's another example.

While overriding `@opam/unison` with the following,

```json
    "@opam/unison": {
      "version": "opam:2.53.4",
      "override": {
        "buildsInSource": "_build",
        "buildEnv": {
          "HOME": "#{$cur__install}",
          "OSTYPE": "#{os == 'windows' ? 'cygwin': ''}",
          "OSARCH": "#{os == 'windows' ? 'win32': ''}",
          "CC": "#{os == 'windows' ? 'x86_64-w64-mingw32-gcc.exe': 'gcc'}"
        },
        "build": "dune build -p unison",
        "install": "esy-installer ./unison.install",
        "dependencies": {
          "@opam/dune": "*",
          "ocaml": "*"
        }
      }
    }
```

it was necesary to specify `esy-installer ...` command since `unison` package contained multiple `.install` files after the build.

`esy-installer` is kind of like `dune install` command, except that it was written with esy's sandbox in mind.
