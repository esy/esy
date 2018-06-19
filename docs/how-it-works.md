---
id: how-it-works
title: How esy works
---

* [Build Steps](#build-steps)
* [Directory Layout](#directory-layout)
  * [Global Cache](#global-cache)
  * [Top Level Project Build Artifacts](#top-level-project-build-artifacts)
  * [Integration with OPAM packages repository](#integration-with-opam-packages-repository)
    * [Consuming published OPAM packages](#consuming-published-opam-packages)
    * [Converting OPAM packages manually](#converting-opam-packages-manually)
    * [Implementation notes](#implementation-notes)

### Build Steps

The `build` entry in the `esy` config object is an array of build steps executed in sequence.

There are many built-in environment variables that are automatically available
to you in your build steps. Many of these have been adapted from other compiled
package managers such as OPAM or Cargo. They are detailed in the [PJC](https://github.com/jordwalke/PackageJsonForCompilers) spec
which `esy` attempts to adhere to.

For example, the environment variable `$cur__target_dir` points to the location where `esy` expects to find your build artifacts. `$cur__install` represents a directory that you are
expected to install your final artifacts into.

A typical configuration might build the artifacts into the special build
destination, and then copy the important artifacts into the final installation
location (which is the cache).

### Directory Layout

Here's a general overview of the directory layout created by various `esy`
commands.

#### Global Cache

When building projects, most globally cached artifacts are stored in `~/.esy`.

    ~/.esy/
     ├─ OtherStuffHereToo.md
     └─ 3___long_enough_padding_for_relocating_binaries___/
        ├── b # build dir
        ├── i # installation dir
        └── s # staging dir

The global store's `_build` directory contains the logs for each package build (whether it was successful or not). The `_install` contains the final
compilation artifacts that should be retained.

#### Top Level Project Build Artifacts

Not all artifacts are cached globally. Build artifacts for any symlinked
dependencies (using `yarn link`) are stored in
`./node_modules/.cache/_esy/store` which is just like the global store, but for
your locally symlinked projects, and top level package.

This local cache doesn't have the dirtyling logic as the global store for
(non-symlinked) dependencies. Currently, both symlinked dependencies and your
top level package are both rebuilt every time you run `esy build`.

Your top level package is build within its source tree, not in a copy of the
source tree, but as always your package can (and should try to) respect the out
of source destination `$cur__target_dir`.

Cached environment computations (for commands such as `esy cmd`) are stored in
`./node_modules/.cache/_esy/bin/command-env`

A convenience executable that runs arbitrary commands within the `command-env`
is stored at `./node_modules/.cache/_esy/bin/command-exec`.

Support for "ejecting" a build is computed and stored in
`./node_modules/.cache/_esy/build-eject`.

    ./node_modules/
     └─ .cache/
        └─ _esy/
           ├─ bin/
           │  ├─ build-env
           │  └─ command-env
           ├─ build-eject/
           │  ├─ Makefile
           │  ├─ ...
           │  ├─ eject-env
           │  └─ node_modules   # Perfect mirror
           │     └─ FlappyBird
           │        ├─ ...
           │        └─ eject-env
           └─ store/
              ├── ThisIsBuildCacheForSymlinked
              ├── b
              ├── i
              └── s

#### Advanced Build Environment

The following environment variables are related to the package that is
currently being built, which might be _different_ than the package that
owns the package.json where these variables occur. This is because
when building a package, the build environment is computed by traversing
its dependencies and aggregating exported environment variables transitively,
which may refer to the "cur" package - the package *cur*ently being built.

* `$cur__install`
* `$cur__target_dir`
* `$cur__root`
* `$cur__name`
* `$cur__version`
* `$cur__depends`
* `$cur__bin`
* `$cur__sbin`
* `$cur__lib`
* `$cur__man`
* `$cur__doc`
* `$cur__stublibs`
* `$cur__toplevel`
* `$cur__share`
* `$cur__etc`

This is based on [PJC](https://github.com/jordwalke/PackageJsonForCompilers) spec.

#### Integration with OPAM packages repository

##### Consuming published OPAM packages

During `esy install` command running Esy resolves dependencies within the
`@opam/*` npm scope using a special resolver which looks for a package in the
OPAM repository.

It converts OPAM package metadata into `package.json` with `esy` config section
inferred and installs the OPAM package like any regular package inside the
project's `node_modules` directory.

For example, after running the following command:

```bash
esy add @opam/lwt
```

You can inspect `node_modules/@opam/lwt/package.json` for Esy build configuration.

##### Converting OPAM packages manually

Esy provides a command `esy import-opam` which can be used like this to convert
OPAM packages manually into `package.json`-based packages. For example to
convert an lwt package from a repo:

```bash
git clone https://github.com/ocsigen/lwt
cd lwt
esy import-opam lwt 3.1.0 ./opam > package.json
```

##### Implementation notes

Code for `esy install` command (along with `esy add` and `esy install-cache`
commands) is based on a fork of yarn — [esy-ocaml/esy-install](https://github.com/esy/esy-install).

OPAM to `package.json` metadata convertation is handled by
[esy-ocaml/esy-opam](https://github.com/esy-ocaml/esy-opam).
