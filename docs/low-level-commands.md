---
id: low-level-commands
title: Low Level Commands
---

esy provides a set of low level commands which enable more configurable
workflows.

Such commands are grouped into two concerns:

- Managing installations
- Managing build environments

## Managing installations

The following commands helps managing installations of dependencies.

The end product of an installation procedure is a solution lock (`esy.lock`
directory) which describes the package graph which corresponds to the
constraints defined in `package.json` manifest.

User typically don't need to run those commands but rather use `esy install`
invocation or `esy` invocation which performs installation procedure as needed.

### `esy solve`

`esy solve` command performs dependency resolution and produces the solution lock
(`esy.lock` directory). It doesn't fetch package sources.

### `esy fetch`

`esy fetch` command fetches package sources as defined in `esy.lock` making
package sources available for the next commands in the pipeline.

## Managing build environment

The following commands operate on a project which has the `esy.lock` produced
and sources fetched.

### `esy build-dependencies`

`esy build-dependencies` command builds dependencies in a given build
environment for a given package:

```bash
esy build-dependencies [OPTION]... [PACKAGE]
```

Note that by default only regular packages are built, to build linked packages
one need to pass `--all` command line flag.

Arguments:

- `PACKAGE` (optional, default: `root`) Package to build dependencies for.

Options:

- `--all` Build all dependencies (including linked packages)

- `--release` Force to use "esy.build" commands (by default "esy.buildDev"
  commands are used)

  By default linked packages are built using `"esy.buildDev"` commands defined
  in their corresponding `package.json` manifests, passing `--release` makes
  build process use `"esy.build"` commands instead.

### `esy command-exec`

`esy-exec-command` command executes a command in a given environment:

```bash
esy exec-command [OPTION]... PACKAGE COMMAND...
```

Arguments:

- `COMMAND` (required) Command to execute within the environment.

- `PACKAGE` (required) Package in which environment execute the command.

Options:

- `--build-context` Initialize package's build context before executing the command.

  This provides the identical context as when running package build commands.

- `--envspec=DEPSPEC` Define DEPSPEC expression which is used to construct the
  environment for the command invocation.

- `--include-build-env` Include build environment.

- `--include-current-env` Include current environment.

- `--include-npm-bin` Include npm bin in `$PATH`.

### `esy print-env`

`esy-print-env` command prints a configured environment on stdout:

```bash
esy print-env [OPTION]... PACKAGE
```

Arguments:

- `PACKAGE` (required) Package in which environment execute the command.

Options:

- `--envspec=DEPSPEC` Define DEPSPEC expression which is used to construct the
  environment for the command invocation.

- `--include-build-env` Include build environment. This includes some special
  `$cur__*` envirironment variables, as well as environment variables configured
  in the `esy.buildEnv` section of the package config.

- `--include-current-env` Include current environment.

- `--include-npm-bin` Include npm bin in `$PATH`.

- `--json` Format output as JSON

## DEPSPEC

Some commands allow to define how an environment is constructed for each package
based on other packages in a dependency graph (see `--envspec` command option
described above). This is done via DEPSPEC expressions.

There are the following constructs available in DEPSPEC:

- `self` refers to the current package, for which the environment is being constructed.

- `root` refers to the root package in an esy project.

- `dependencies(PKG)` refers to a set of `"dependencies"` of `PKG` package.

- `devDependencies(PKG)` refers to a set of `"devDependencies"` of `PKG` package.

- `EXPR1 + EXPR2` refers to a set of packages found in `EXPR1` or `EXPR2`
  (union).

Examples:

- Dependencies of the current package:
  ```bash
  dependencies(self)
  ```
  This constructs the environment which is analogous to the environment used to
  build packages.

- Dev dependencies of the root package:
  ```bash
  devDependencies(root)
  ```

- Dependencies of the current package and the package itself:
  ```bash
  dependencies(self) + self
  ```
  This constructs the environment which is analogous to the environment used in
  `esy x CMD` invocations.


