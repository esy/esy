# Esy

`package.json` workflow for native development with Reason/OCaml.

[![Travis](https://img.shields.io/travis/esy/esy.svg)](https://travis-ci.org/esy/esy)
[![npm](https://img.shields.io/npm/v/esy.svg)](https://www.npmjs.com/package/esy)
[![npm (tag)](https://img.shields.io/npm/v/esy/next.svg)](https://www.npmjs.com/package/esy)

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->


- [What](#what)
  - [For npm users](#for-npm-users)
  - [For OPAM users](#for-opam-users)
  - [In depth](#in-depth)
- [Install](#install)
- [Workflow](#workflow)
  - [Try An Example](#try-an-example)
  - [Configuring Your `package.json`](#configuring-your-packagejson)
    - [Specify Build & Install Commands](#specify-build--install-commands)
      - [`esy.build`](#esybuild)
      - [`esy.install`](#esyinstall)
    - [Enforcing Out Of Source Builds](#enforcing-out-of-source-builds)
    - [Exported Environment](#exported-environment)
    - [Esy configuration](#esy-configuration)
      - [Prefix path](#prefix-path)
  - [Esy Environment Reference](#esy-environment-reference)
    - [Build Environment](#build-environment)
    - [Command Environment](#command-environment)
  - [Variable substitution syntax](#variable-substitution-syntax)
  - [Esy Command Reference](#esy-command-reference)
- [How Esy Works](#how-esy-works)
  - [Build Steps](#build-steps)
  - [Directory Layout](#directory-layout)
    - [Global Cache](#global-cache)
    - [Top Level Project Build Artifacts](#top-level-project-build-artifacts)
    - [Advanced Build Environment](#advanced-build-environment)
    - [Integration with OPAM packages repository](#integration-with-opam-packages-repository)
      - [Consuming published OPAM packages](#consuming-published-opam-packages)
      - [Converting OPAM packages manually](#converting-opam-packages-manually)
      - [Implementation notes](#implementation-notes)
- [Developing](#developing)
  - [Testing Locally](#testing-locally)
  - [Running Tests](#running-tests)
  - [Issues](#issues)
  - [Publishing Releases](#publishing-releases)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## What

### For npm users

For those familiar with [npm][], esy allows to work with Reason/OCaml projects
within the familiar npm-like workflow:

- Declare dependencies in `package.json`.

- Install and build with `esy install` and `esy build` commands. Dependencies'
  source code end up in `node_modules`.

- Share your work with other developers by publishing on npm registry and/or github.

- Access packages published on [OPAM][] (a package registry for OCaml) via
  `@opam` npm scope (for example `@opam/lwt` to pull `lwt` library from OPAM).

### For OPAM users

For those who familiar with [OPAM][], esy provides a powerful alternative (to
the `opam` tool, OPAM packages are still accessible with Esy):

- Manages OCaml compilers and dependencies on a per project basis.

- Sandboxes project environment by exposing only those packages which are
  defined as dependencies.

- Fast parallel builds which are agressively cached (even across different projects).

- Keeps the ability to use packages published on OPAM repository.

### In depth

- Project metadata is managed inside `package.json`.

- Parallel builds.

- Clean environment builds for reproducibility.

- Global build cache automatically shared across all projects — initializing new
  projects is often cheap.

- File system sandboxing to prevent builds from mutating locations they don't
  own.

- Solves environment variable pain. Native toolchains rely heavily on environment
  variables, and `esy` makes them behave predictably, and usually even gets them
  out of your way entirely.

- Allows symlink workflows for local development (by enforcing out-of-source
  builds). This allows you to work on several projects locally, make changes to
  one project and the projects that depend on it will automatically know they
  need to rebuild themselves.

- Run commands in project environment quickly `esy <anycommand>`.

- Makes sharing of native projects easier than ever by supporting "eject to `Makefile`".

  - Build dependency graph without network access.

  - Build dependency graph where `node` is not installed and where no package
    manager is installed.

## Install

```
% npm install --global esy
```

If you had installed esy previously:

```
% npm uninstall --global --update esy
```

## Workflow

Esy provides a single command called `esy`.

The typical workflow is to `cd` into a directory that contains a `package.json`
file, and then perform operations on that project.

### Try An Example

There are example projects:

- [OCaml + jbuilder project][esy-ocaml-project]
- [Reason + jbuilder project][esy-reason-project]

The typical workflow looks like this:

0. Install esy:
    ```
    % npm install -g esy
    ```

1. Clone the project:
    ```
    % git clone git@github.com:esy-ocaml/esy-ocaml-project.git
    % cd esy-ocaml-project
    ```

2. Install project's dependencies source code:
    ```
    % esy install
    ```

3. Perform an initial build of the project's dependencies and of the project
   itself:
    ```
    % esy build
    ```

4. Test the compiled executables inside the project's environment:
    ```
    % esy ./_build/default/bin/hello.exe
    ```

5. Hack on project's source code and rebuild the project:
    ```
    % esy build
    ```

Also:

6. It is possible to invoke any command from within the project's sandbox.
   For example build & run tests with:
    ```
    % esy make test
    ```
   You can run any command command inside the project environment by just
   prefixing it with `esy`:
    ```
    % esy <anycommand>
    ```

7. To shell into the project's sandbox:
    ```
    % esy shell
    ```

8. For more options:
    ```
    % esy help
    ```

### Configuring Your `package.json`

`esy` knows how to build your package and its dependencies by looking at the
`esy` config section in your `package.json`.

This is how it looks for a [jbuilder][] based project:

```
{
  "name": "example-package",
  "version": "1.0.0",

  "esy": {
    "build": [
      "jbuilder build"
    ],
    "install": [
      "esy-installer"
    ],
    "buildsinsource": "_build"
  },

  "dependencies": {
    "anotherpackage": "1.0.0",
    "@esy-ocaml/esy-installer"
  }
}
```

#### Specify Build & Install Commands

The crucial pieces of configuration are `esy.build` and `esy.install` keys, they
specify how to build and install built artifacts.

##### `esy.build`

Describe how your project's default targets should be built by specifying
a list of commands with `esy.build` config key.

For example for a [jbuilder][] based project you'd want to call `jbuilder build`
command.

```
{
  "esy": {
    "build": [
      "jbuilder build",
    ]
  }
}
```

Commands specified in `esy.build` are always executed for the root's project
when user calls `esy build` command.

[Esy variable substitution syntax](#variable-substitution-syntax) can be used to
declare build commands.

##### `esy.install`

Describe how you project's built artifacts should be installed by specifying a
list of commands with `esy.install` config key.

```
{
  "esy": {
    "build": [...],
    "install": [
      "esy-installer"
    ]
  }
}
```

For `jbuilder` based projects (and other projects which maintain `.install` file
in opam format) that could be just a single `esy-installer` invokation. The
command is a thin wrapper over `opam-installer` which configures it with Esy
defaults.

[Esy variable substitution syntax](#variable-substitution-syntax) can be used to
declare install commands.

#### Enforcing Out Of Source Builds

Esy requires packages to be built "out of source".

It allows Esy to separate source code from built artifacts and thus reuse the
same source code location with several projects/sandboxes.

There are three modes which are controlled by `esy.buildsInSource` config key:

```
{
  "esy": {
    "build": [...],
    "install": [...],
    "buildInSource": "_build" | false | true,
  }
}
```

Each mode changes how Esy executes [build commands](#esybuild). This is how
those modes work:

- `"_build"`

  Build commands can place artifacts inside the `_build` directory of the
  project's root (`$cur__root/_build` in terms of Esy [build
  environment](#build-environment)).

  This is what [jbuilder][] or [ocamlbuild][] (in its default configuration)
  users should be using as this matches those build systems' conventions.

- `false` (default if key is ommited)

  Build commands should use `$cur__target_dir` as the build directory.

- `true`

  Build commands cannot be configured to use a different directory than the
  projects root directory. In this case Esy will defensively copy project's root
  into `$cur__target_dir` and run build commands from there.

  This is the mode which should be used as the last resort as it degrades
  perfomance of the builds greatly by placing correctness as a priority.

#### Exported Environment

Packages can configure how they contribute to the environment of the packages
which depend on them.

To add a new environment variable to the Esy [build
environment](#build-environment) packages could specify `esy.exportedEnv` config
key:

```
{
  "name": "mylib",
  "esy": {
    ...,
    "exportedEnv": {
      "CAML_LD_LIBRARY_PATH": "#{mylib.lib : $CAML_LD_LIBRARY_PATH}",
      "scope": "global"
    }
  }
}
```

In the example above, the configuration *exports* (in this specific case it
*re-exports* it) an environment variable called `$CAML_LD_LIBRARY_PATH` by
appending `$mylib__lib` to its previous value.

Also note the usage of [Esy variable substitution
syntax](#variable-substitution-syntax) to define the value of the
`$CAML_LD_LIBRARY_PATH` variable.

#### Esy configuration

Esy can be configured via environment variables or via `.esyrc`.

Esy looks for `.esyrc` configuration in two locations (sorted by priority):

1. Sandbox directory (usually the current working dir, where `package.json`
   resides): `$ESY__PREFIX/.esyrc`

2. Home directory: `$HOME/.esyrc`

##### Prefix path

Prefix path determines where Esy puts its global store and other caches. By
default it is set to `$HOME/.esy`.

To change the default you can either:

- Set `$ESY__PREFIX` environment variable.
- Add `esy-prefix-path: /path/to/esy/prefix` to `.esyrc`

### Esy Environment Reference

For each project Esy manages:

- *build environment* — an environment which is used to build the project

- *command environment* — an environment which is used running text editors/IDE
  and for general testing of the built artfiacts

#### Build Environment

The following environment variables are provided by Esy:

- `$SHELL`
- `$PATH`
- `$MAN_PATH`
- `$OCAMLPATH`
- `$OCAMLFIND_DESTDIR`
- `$OCAMLFIND_LDCONF`
- `$OCAMLFIND_COMMANDS`

#### Command Environment

Currently the command environment is identical to build environment sans the
`$SHELL` variable which is non-overriden and equals to the `$SHELL` value of a
user's environment.


### Variable substitution syntax

Your `package.json`'s `esy` configuration can include "interpolation" regions written
as `#{ }`, where `esy` "variables" which will automatically be substituted
with their corresponding values.

For example, if you have a package named `@company/widget-factory` at version
`1.2.0`, then its `esy.build` field in `package.json` could be specified as:

```json
   "build": "make #{@company/widget-factory.version}",
```

and `esy` will ensure that the build command is interpreted as `"make 1.2.0"`.
In this example the interpolation region includes just one `esy` variable
`@company/widget-factory.version` - which is substituted with the version number
for the `@company/widget-factory` package.

Package specific variables are prefixed with their package name, followed
by an `esy` "property" of that package such as `.version` or `.lib`.

`esy` also provides some other built in variables which help with path and environment
manipulation in a cross platform manner.

**Supported Variable Substitutions:**

Those variables refer to the values defined for the current package:

- `self.bin`
- `self.sbin`
- `self.lib`
- `self.man`
- `self.doc`
- `self.stublibs`
- `self.toplevel`
- `self.share`
- `self.etc`
- `self.install`
- `self.target_dir`
- `self.root`
- `self.name`
- `self.version`
- `self.depends`

You can refer to the values defined for other packages by using the respective
`package-name` prefix:

- `package-name.bin`
- `package-name.sbin`
- `package-name.lib`
- `package-name.man`
- `package-name.doc`
- `package-name.stublibs`
- `package-name.toplevel`
- `package-name.share`
- `package-name.etc`
- `package-name.install`
- `package-name.target_dir`
- `package-name.root`
- `package-name.name`
- `package-name.version`
- `package-name.depends`

The following constructs are also allowed inside "interpolation" regions:

- `$PATH`, `$cur__bin` : environment variable references
- `'hello'`, `'lib'` : string literals
- `/` : path separator (substituted with the platform's path separator)
- `:` : env var value separator (substituted with platform's env var separator `:`/`;`).

You may join many of these `esy` variables together inside of an interpolation region
by separating the variables with spaces. The entire interpolation region will be substituted
with the concatenation of the space separated `esy` variables.

White space separating the variables are not included in the concatenation, If
you need to insert a literal white space, use `' '` string literal.



Examples:

- ```
  "#{pkg.bin : $PATH}"
  ```

- ```
  "#{pkg.lib / 'stublibs' : $CAML_LD_LIBRARY_PATH}"
  ```

### Esy Command Reference

```

Usage: esy <command> [--help] [--version]

install               Installs packages declared in package.json.
i

build                 Builds everything that needs to be built, caches
b                     results. Builds according to each package's "esy"
                      entry in package.json. Before building each package,
                      the environment is scrubbed clean then created according
                      to dependencies.

build <command>       Builds everything that needs to be build, caches
b <command>           results. Then runs a command inside the root package's
                      build environment.

shell                 The same as esy build-shell, but creates a "relaxed"
                      environment - meaning it also inherits your existing
                      shell.

add <package>         Add a specified package to dependencies and installs it.

release TYPE          Create a release of type TYPE ("dev", "pack" or "bin").

print-env             Prints esy environment on stdout.

build-shell [path]    Drops into a shell with environment matching your
                      package's build environment. If argument is provided
                      then it should point to the package inside the current
                      sandbox — that will initialize build shell for that
                      specified package.

build-eject           Creates node_modules/.cache/esy/build-eject/Makefile,
                      which is later can be used for building without the NodeJS
                      runtime.

                      Unsupported form: build-eject [cygwin | linux | darwin]
                      Ejects a build for the specific platform. This
                      build-eject form is not officially supported and will
                      be removed soon. It is currently here for debugging
                      purposes.

install-cache         Manage installation cache (similar to 'yarn cache'
                      command).

import-opam           Read a provided opam file and print esy-enabled
                      package.json conents on stdout. Example:

                        esy import-opam lwt 3.0.0 ./opam

config ls|get         Query esy configuration.

help                  Print this message.

version               Print esy version and exit

<command>             Executes <command> as if you had executed it inside of
                      esy shell.

```

## How Esy Works

### Build Steps

The `build` entry in the `esy` config object is an array of build steps executed in sequence.

There are many build in environment variables that are automatically available
to you in your build steps. Many of these have been adapted from other compiled
package managers such as OPAM or Cargo. They are detailed in the [PJC][] spec
which `esy` attempts to adhere to.

For example, the environment variables `$cur__target_dir` is an environment
variable set up which points to the location that `esy` expects you to place
your build artifacts into. `$cur__install` represents a directory that you are
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

The global store's `_build` directory contains the logs for each package that
is build (whether or not it was successful). The `_install` contains the final
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
currently being built, which might be *different* than the package that
owns the package.json where these variables occur. This is because
when building a package, the build environment is computed by traversing
its dependencies and aggregating exported environment variables transitively,
which may refer to the "cur" package - the package *cur*ently being built.

- `$cur__install`
- `$cur__target_dir`
- `$cur__root`
- `$cur__name`
- `$cur__version`
- `$cur__depends`
- `$cur__bin`
- `$cur__sbin`
- `$cur__lib`
- `$cur__man`
- `$cur__doc`
- `$cur__stublibs`
- `$cur__toplevel`
- `$cur__share`
- `$cur__etc`


This is based on [PJC][] spec.

#### Integration with OPAM packages repository

##### Consuming published OPAM packages

During `esy install` command running Esy resolves dependencies within the
`@opam/*` npm scope using a special resolver which looks for a package in the
OPAM repository.

It converts OPAM package metadata into `package.json` with `esy` config section
inferred and installs the OPAM package like any regular package inside the
project's `node_modules` directory.

For example, after running the following command:

```
% esy add @opam/lwt
```

You can inspect `node_modules/@opam/lwt/package.json` for Esy build configuration.

##### Converting OPAM packages manually

Esy provides a command `esy import-opam` which can be used like this to convert
OPAM packages manually into `package.json`-based packages. For example to
convert an lwt package from a repo:

```
% git clone https://github.com/ocsigen/lwt
% cd lwt
% esy import-opam lwt 3.1.0 ./opam > package.json
```

##### Implementation notes

Code for `esy install` command (along with `esy add` and `esy install-cache`
commands) is based on a fork of yarn — [esy-ocaml/esy-install][].

OPAM to `package.json` metadata convertation is handled by
[esy-ocaml/esy-opam][].

## Developing

To make changes to `esy` and test them locally:

```
% git clone git://github.com/esy/esy.git
% cd esy
% make bootstrap
```

Run:

```
% make
```

to see the description of development workflow.

### Testing Locally

```
% make build-release
% npm remove -g esy
% npm install -g dist
```

Now you may run `esy` commands using your local version of `esy`.


### Running Tests

```
% make test
```

### Issues

Issues are tracked at [esy/esy][].

### Publishing Releases

On a clean branch off of `origin/master`, run:

```
% make bump-patch-version publish
```

to bump the patch version, tag the release in git repository and publish the
tarball on npm.

To publish under custom release tag:

```
% make RELEASE_TAG=next bump-patch-version publish
```

Release tag `next` is used to publish preview releases.

[esy-ocaml-project]: https://github.com/esy-ocaml/esy-ocaml-project
[esy-reason-project]: https://github.com/esy-ocaml/esy-reason-project
[esy/esy]: https://github.com/esy/esy
[esy-ocaml/esy-install]: https://github.com/esy-ocaml/esy-install
[esy-ocaml/esy-opam]: https://github.com/esy-ocaml/esy-opam
[OPAM]: https://opam.ocaml.org
[npm]: https://npmjs.org
[Reason]: https://reasonml.github.io
[OCaml]: https://ocaml.org
[jbuilder]: http://jbuilder.readthedocs.io
[ocamlbuild]: https://github.com/ocaml/ocamlbuild/blob/master/manual/manual.adoc
[PJC]: https://github.com/jordwalke/PackageJsonForCompilers
