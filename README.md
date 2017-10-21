# Esy

`package.json` workflow for compiled languages.

## What

- Makes compiled projects work with `package.json` package managers.

- Makes it trivial to share natively compiled projects with anyone - even if they don't
  have a package manager installed.

- Makes native projects build faster.

- Widens the reach of OPAM packages by allowing them to be installed
  by `npm` (the most popular package manager).

## Features

- Directory based projects (like `package.json`).

- Parallel builds.

- Clean environment builds for reproducibility.

- Global build cache automatically shared across all projects. You don't think about the
  cache and don't think about creating "virtual environments" or "switches". `esy`
  figures it out.

- File system sandboxing to prevent builds from mutating locations they don't
  own.

- Solves environment variable pain. Native toolchains rely heavily on environment
  variables, and `esy` makes them behave predictably, and usually even gets them
  out of your way entirely.

- Allows symlink workflows for local development (by enforcing out-of-source
  builds). This allows you to work on several projects locally, make changes to
  one project and the projects that depend on it will automatically know they
  need to rebuild themselves.

- Run commands in project environment quickly `esy any command`.

- Makes sharing of native projects easier than ever by supporting "eject to `Makefile`".
  - Build dependency graph without network access.
  - Build dependency graph where `node` is not installed and where no package manager
    is installed.

## Install

```
npm install -g esy
```

If you had installed esy previously:

```
npm uninstall -g esy
npm install -g esy
```

## Workflow

`esy` provides one global command (`esy`) which manages compiled, local
`package.json` projects.

The typical workflow is to `cd` into a directory that contains a `package.json`
file, and then perform operations on that project.

```
% esy

  Usage: esy <command> [--help] [--version]

  install               Installs packages declared in package.json.

  build                 Builds everything that needs to be built, caches
                        results. Builds according to each package's "esy"
                        entry in package.json. Before building each package,
                        the environment is scrubbed clean then created according
                        to dependencies.

  shell                 The same as esy build-shell, but creates a "relaxed"
                        environment - meaning it also inherits your existing
                        shell.

  release TYPE          Create a release of type TYPE ("dev", "pack" or "bin").

  print-env             Prints esy environment on stdout.

  build-shell           Drops into a shell with environment matching your
                        package's build environment.

  build-eject           Creates node_modules/.cache/esy/build-eject/Makefile,
                        which is later can be used for building without the NodeJS
                        runtime.

                        Unsupported form: build-eject [cygwin | linux | darwin]
                        Ejects a build for the specific platform. This
                        build-eject form is not officially supported and will
                        be removed soon. It is currently here for debugging
                        purposes.


  import-opam           Read a provided opam file and print esy-enabled
                        package.json conents on stdout. Example:

                          esy import-opam lwt 3.0.0 ./opam

  <command>             Executes <command> as if you had executed it inside of
                        esy shell.

```

## Try An Example

```
# Make sure esy is installed
npm install -g esy

# Clone the example esy project
git clone git@github.com:esy-ocaml/esy-ocaml-project.git

cd esy-ocaml-project

# Install project dependencies
esy install

# Build project
esy build

# Now run some commands inside the project's environment
esy ./_install/bin/hello.native

# Shell into project's environment
esy shell
```

## Enjoy The Cache

The previous example may have taken 10 minutes to build, but with `esy`'s
cache, the second time will be instant.

```
rm -rf node_modules
esy install
esy build
```

`esy`'s cache is package-granular and takes into account anything that could
influence the build. If you create another project with 90% of the same
dependencies, there's a good chance that 90% of the build is performed
instantly (pulled from cache).


## Configuring Your `package.json`

`esy` knows how to build your package and its dependencies by looking at the
`"esy"` config object in your `package.json`.

```
{
  "name": "example-package",
  "version": "1.0.0",

  "esy": {
    "build": [
      "make --buildDest=$cur__target_dir",
      "cp $cur__target_dir/bin/* $cur__install/bin/"
    ],
    "exportedEnv": {
      "PATH": {
        "val": "$PATH:$cur__install/bin",
        "scope": "global"
      }
    },
  },

  "dependencies": {
    "AnotherPackage": "1.0.0"
  }
}
```

#### Build Steps

The `build` entry in the `esy` config object is an array of build steps executed in sequence.

There are many build in environment variables that are automatically available
to you in your build steps. Many of these have been adapted from other compiled
package managers such as OPAM or Cargo. They are detailed in the
[PJC](https://github.com/jordwalke/PackageJsonForCompilers) spec which `esy`
attempts to adhere to.

For example, the environment variables `$cur__target_dir` is an environment
variable set up which points to the location that `esy` expects you to place
your build artifacts into. `$cur__install` represents a directory that you are
expected to install your final artifacts into.

A typical configuration might build the artifacts into the special build
destination, and then copy the important artifacts into the final installation
location (which is the cache).

### Exported Environment

In the example above, the configuration also *exports* an environment variable,
specifically, the `PATH` environment variable, so that other packages that
depend on this package can *see* those binary artifacts.

Because exporting the `PATH` to contain the `$cur__install/bin` directory is so
common, `esy` performs this automatically. It's still up to you to export any
other environment variables.

> Note: Right now, packages that depend on your package have their `PATH`
> augmented with *your* package's `$cur__install/bin` - with `scope: global`.
> This should be improved - it shouldn't be globally visible, it should only be
> visible to packages that have an immediate dependency on your package.

> Note: You could imagine implementing npm's `bin` feature on top of this - and
> then some.


## Optional Config Variables

```
{
  ...
  "esy": {
    ...
    "buildsInSource": true
  }
}
```

- `buildsInSource` should be set to true if your package does not respect out
  of source builds. `esy build` will keep packages honest using OS-level file
  system sandboxing, warning when a package writes to its own source directory
  without marking itself `buildsInSource:true`. For packages that build in
  source, their package contents are copied to a defensive copy before
  building.


## Making Esy Awesome

- [Make `esy` the standard editor environment
  config](https://github.com/jordwalke/esy/issues/70).
- [`esy` Dashboard / Assistant](https://github.com/jordwalke/esy/issues/71)
- [Render to ninja / Powershell](https://github.com/jordwalke/esy/issues/72)

# Contributing


### Directory Layout

Here's a general overview of the directory layout created by various `esy`
commands.

##### Global Cache

When building projects, most globally cached artifacts are stored in `~/.esy`.

    ~/.esy/
     ├─ OtherStuffHereToo.md
     └─ v3.x.x___long_enough_padding_for_relocating_binaries___/
        ├── b # build dir
        ├── i # installation dir
        └── s # staging dir

The global store's `_build` directory contains the logs for each package that
is build (whether or not it was successful). The `_install` contains the final
compilation artifacts that should be retained.

#### Top Level Project Build Artifacts

###### Local Build Cache, Build Eject And Environment Cache

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
`./node_modules/.cache/_esy/command-env`

Support for "ejecting" a build is computed and stored in
`./node_modules/.cache/_esy/build-eject`.

    ./node_modules/
     └─ .cache/
        └─ _esy/
           ├─ command-env
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

#### Debugging

###### Package Cache

`esy` currently uses Yarn to perform the installs, but ensures that it uses its
own isolated package cache. (note: this is different than `esy`'s build cache).
You can see where this cache is by running:

```
dirname $(realpath `which esy`)
```

The reason why `esy` has its own cache, and the reason why it is inside of its
own binary installation location, is to ensure that when you upgrade `esy`, the
package cache will be purged. This is because many of `esy`'s opam packages are
precomputed and stored within `esy`'s internals, but then Yarn's cache will
store them in its own cache. Across `esy` upgrades, we may change how we
precompute those opam package.json's and want the cache busted.

#### Issues

Issues are tracked at [esy-ocaml/esy](https://github.com/esy-ocaml/esy-core).

#### Tests

```
npm run test
```

#### Developing

To make changes to `esy-core` and test them locally:

    % git clone git://github.com/esy-ocaml/esy-core.git
    % cd esy-core
    % make bootstrap

Run:

    % make

to see the description of development workflow.

#### Pushinging releases

On a clean branch off of `origin/master`, run

    % make bump-patch-version publish

#### Debugging Failed `esy build`

When  debugging esy build — do the following:

1. `esy build-eject` creates `/node_modules/.cache/_esy/build-eject/Makefile`
2. `make -f ./node_modules/.cache/_esy/build-eject/Makefile PKG_NAME.shell` will put you in a build env shell
3. Try to run commands specified in `package.json's` esy build config and see what goes wrong.

If the package is a converted opam package, you might want to inspect the
generated package.json, as well as the original opam file and make sure that it
was converted correctly.
