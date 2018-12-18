---
id: version-0.3.4-commands
title: Commands
original_id: commands
---

Reference of all available esy commands. The most common commands are [`esy
install`](#esy-install) and [`esy build`](#esy-build).

## Main commands

### `esy`

The default command combines `esy install` and `esy build` and runs them in
consecutively.

### `esy install`

Install dependencies declared in `package.json`:

```bash
% esy install
```

If the file `esy.lock` (an analogue of `yarn.lock`) exists then it will be used
to resolve dependencies' version constraints to concrete versions, otherwise
constraints resolution will be performed and saved to a fresh `esy.lock`.

This command is based on `yarn` and accepts the same command line arguments and
options.

### `esy build`

Ensure all dependencies are built and then execute the project's build commands.
Note that esy tries to reuse built artifacts as much as possible, even across
different sandboxes. That means that usually `esy build` executes only root
project's build process.

Example:

```bash
% esy build
```

## Run commands in the specified environment

These commands allow to execute arbitrary commands in esy's managed
environments. For more info about environment types see [corresponding
docs][environment.md].

### `esy build <anycommand>`

Run command `<anycommand>` in the build environment.

For example, we can see which `ocamlfind` libraries are available:

```bash
% esy build ocamlfind
```

Another example usage would be to execute a build process for some specific
build target:

```bash
% esy build bin/hello.exe
```

This is useful when you want to perform a build just for a subset of build
outputs.

### `esy build-shell [<path/to/package>]`

Initialize shell with build environment.

Example:

```bash
% esy build-shell
```

If `<path/to/package>` argument is passed then the build shell is initialied for
the specified package:

```
% esy build-shell ./node_modules/@opam/lwt
```

This command is useful for debugging failing builds.

### `esy <anycommand>`

Run command `<anycommand>` in command environment.

Example:

```bash
% esy vim ./bin/hello.re
```

As command environment contains development time dependencies (like
`@opam/merlin`) `vim` program will have access to those.

### `esy shell`

Initialize shell with command environment.

Example:

```bash
% esy shell
```

### `esy x <anycommand>`

Execute command `<anycommand>` in test environment.

Example:

```
% esy x hello
```

This invocation puts root project's executables in `$PATH` thus it's useful to
test the project as it was installed.

## Sandbox introspection

### `esy ls-builds`

Prints a dependency tree with status of each package.

Example:

```bash
% esy ls-builds
```

### `esy ls-libs`

Prints a dependency tree with all available libraries.

Example:

```bash
% esy ls-libs
```

### `esy ls-modules`

Prints a dependency tree with all available libraries and modules.

Example:

```bash
% esy ls-modules
```

### `esy build-env`

Prints build environment on stdout.

Example:

```bash
% esy build-env
```

### `esy command-env`

Prints command environment on stdout.

Example:

```bash
% esy command-env
```

## Other commands

### `esy add`

Adds a new dependency for a project.

Example:

```bash
% esy add @opam/lwt
```

### `esy release`

Produce an npm package with pre built binaries for the current platform inside
the `_release` directory.

See [Building Releases](release.md) for more info.

### `esy export-dependencies`

Export dependencies of the root project from a build store.

Example:

```bash
% esy export-dependencies
```

The invocation above produces a set of tarballs inside `_export` directory.
Those tarballs can be shipped to another host and imported into build store with
`esy import-build` command.

### `esy export-build`

Export a single build out of a build store.

Example:

```bash
% esy export-build ~/.esy/3/i/ocaml-4.6.0-abcdef90
```

This commands produces `_export/ocaml-4.6.0-abcdef90.tar.gz` tarball which can
be imported into another build store with `esy import-build` command.

### `esy import-build`

Import a single build into a build store.

Import from a previously exported build:

```bash
% esy import-build ./_export/ocaml-4.6.0-abcdef90.tar.gz
```

Import from a build store:

```bash
% esy import-build /path/to/build/store/3/i/ocaml-4.6.0-abcdef90
```
