# Provide API for esy workflows

The motivation of this proposal is to describe a minimal set of primitives which
allow to represent the current (and future) esy workflows.

The end goal is to enable customization of esy workflows by end users.

While it's great to have one single workflow it is likely it won't meet all
needs. The primitives described in this proposal are meant to be used as
building blocks for such customized workflows.

Besides that we are going to describe the current esy workflow using such
primitives. Thus the motivation for introducing such primitives isn't only to
enable custom workflows but to simplify esy's current implementation and provide
users with insights on how high level esy commands work.

The gist of the proposal:

- Introduce DEPSPEC, a language which allows to refer to package dependencies.

- Introduce commands which receive DEPSPEC as an input and perform two main
  tasks - installation of packages and running commands - this is essentially
  what esy does.

- Provide examples of using such language + commands with two workflows:

  - Current workflow

  - Monorepo style workflow

## Introducing DEPSPEC

DEPSPEC stands for DEPendency SPECification language.

The motivation for DEPSPEC is to enable configuration of the scope of esy
commands. Right now esy hardcodes a lot of decisions regarding this (`esy x ...`
adds current packages and its to deps to env, `esy ...` adds deps and devDeps to
env and so on). Instead we want to represent different esy invocations as a
single command + DEPSPEC expression.

DEPSPEC can be defined on top of arbitrary identifiers (we refer to them with
`ID`). For example DEPSPEC used in `esy install-by` command can refer only to
identifiers which represent local packages (a sensible restrictions as other
packages are unknown at this point in workflow) while DEPSPEC used in `esy
exec-by` can represent any package in the solution lock.

Primitives:

- `pkg(ID)` - a package defined by `ID`

  Examples:

  ```
  pkg(package)
  pkg(chalk)
  ```

- `deps(ID)` - a set of `"dependencies"` of the package defined by `ID`

  Examples:

  ```
  deps(chalk)
  ```

- `devDeps(ID)` - a set of `"devDependencies"` of the package defined by `ID`

  Examples:

  ```
  devDeps(package)
  ```

Composition:

- `A+B` union of two specs

  Examples:

  ```
  pkg(package)+deps(package)
  ```

  for each `A`: `A+A` is the same as `A`
  It is commutative: `A+B` is the same as `B+A`
  It is associative: `(A+B)+C` is the same as `A+(B+C)`

  Why it is commutative?

  First, the order is determined by the "depends-on" relation on the set of
  packages and then using artificial lexicographic order within the Equivalence
  class of "depends-on" relation.

## Commands operating on DEPSPEC

## `esy install-by` command

The following command `esy install-by` is proposed to be added to esy:

```
% esy install-by INSTALLSPEC INSTALLLOCK
```

It installs packages according to `INSTALLSPEC` and saves the solution
in `INSTALLLOCK` lock.

`INSTALLSPEC` is an instance of DEPSPEC defined on ids which can only reference
packages defined by local manifests (`*.json` or `*.opam`).

Examples:

- Install dependencies declared in `package.json`:
  ```
  % esy install-by deps(package)
  ```

- Install dependencies and devDependencies declared in `pkg.406.json`:
  ```
  % esy install-by deps(pkg.406)+devDeps(pkg.406)
  ```

## `esy exec-by` command

The following command `esy exec-by` is proposed to be added to esy:

```
% esy exec-by INSTALLOCK [PKGSPEC : (ENVSPEC : ACTION...)...]`
```

It executes a sequence of `ACTION` in the corresponding env constructed
according to `ENVSPEC` for a set of packages specified by `PKGSPEC`.
Packages are resolved using `INSTALLLOCK` lock.

Where

- `PKGSPEC` can be one of:

  - `all` - all packages in the `INSTALLLOCK`
  - `root` - root package in the `INSTALLLOCK`
  - `deps` - all dependencies in the `INSTALLLOCK`
  - `linked` - only linked dependencies in the `INSTALLLOCK`
  - `installed` - all dependencies minus linked dependencies
  - `<anypackage>` - a package specified by `<anypackage>.json` manifest

- `ENVSPEC` is an instance of DEPSPEC, it can refer to the current package
  source as `self` and `root` always refers to the root package, it can also
  refer to any other package in `INSTALLLOCK` by its id.

- `ACTION` can be one of:

  - `build` - a command specified in `"esy.build"` is executed

  - `build-dev` - for linked packages a command specified in `"esy.buildDev"` is
    executed (with a fallback to `"esy.build"` for those packages which didn't
    specify it), for other packages - `"esy.build'` is executed.

  - `<anycommand>` - a command `<anycommand>` is executed.

Examples of using `esy exec-by ...` are provided below.

## Examples

In the following examples we are going to try to represent workflow using
`esy install-by ...` and `esy exec-by ...` invocations.

Note that those invocations are notoriously verbose. That's ok, such invocations
will be hidden behind the shortcuts, probably defined via scripts mechanism.

#### Example: current workflow

The sandbox/package metadata resides in `package.json`.

- Install sandbox dependencies:

  ```
  % esy install-by 'pkg(root)+deps(root)+devDeps(root)' esy.lock
  ```

  (same as `esy install`)

- Run `CMD` in the environment where the root package is built and installed:

  ```
  % esy exec-by esy.lock 'root : deps(self)+devDeps(self)+pkg(self) : CMD'
  ```

  (same as `esy x CMD`)

- Run `CMD` in the command (dev) environment of the root package:

  ```
  % esy exec-by esy.lock 'root : deps(self)+devDeps(self) : CMD'
  ```

  (same as `esy CMD`)

- Run `CMD` in the build environment of the root package:

  ```
  % esy exec-by esy.lock 'root : deps(self) : CMD'
  ```

  (same as `esy b CMD`)

- Build the entire sandbox:

  ```
  % esy exec-by 'esy.lock all : deps(self) : build'
  ```

  (same as `esy build`)

- Build the entire sandbox in dev mode:

  ```
  % esy exec-by esy.lock
      # build all installed deps
      'installed : deps(self) : build'
      # build all linked deps using `build-dev`
      'linked : deps(self) : build-dev'
      # build root package using `build-dev` and mixin `devDeps(self)`
      'root : deps(self)+devDeps(self) : build-dev'
  ```

  (no analogue today)

#### Example: monorepo workflow (reason-native desired flavour)

The sandbox metadata resides in `package.json` while other packages have their own
`*.json` metadata: `chalk.json`, `console.json`, ...

- Install sandbox dependencies:

  ```
  % esy install-by 'pkg(root)+deps(root)+devDeps(root)' esy.lock
  ```

  (same as `esy install`)

- Run `CMD` in the environment where the monorepo packages are built and
  installed:

  ```
  % esy exec-by esy.lock 'root : deps(self)+devDeps(self)+pkg(self) : CMD'
  ```

  (same as `esy x CMD`)

- Run `CMD` in the command (dev) environment:

  ```
  % esy exec-by esy.lock 'root : deps(self)+devDeps(self) : CMD'
  ```

  (same as `esy CMD`)

- `esy b CMD` doesn't make sense as there's no package defined at the root of the sandbox.

- Build the entire sandbox:

  ```
  % esy exec-by esy.lock 'deps : deps(self) : build'
  ```

  (same as `esy build`)

- `esy build-dev` is the same as in the example above

  ```
  % esy exec-by esy.lock
      # build all installed deps
      'installed : deps(self) : build'
      # build all linked deps using `build-dev` and mix root's devDeps
      'linked : deps(self)+devDeps(root) : build-dev'
  ```

- We can build only specific package in a sandbox:

  ```
  % esy exec-by 'chalk : deps(self) : build'
  ```

  dev build:

  ```
  % esy exec-by esy.lock 'chalk : deps(self)+devDeps(root) : build-dev'
  ```

- We can run arbitrary commands `CMD` in the environment of the specified
  package:

  ```
  % esy exec-by esy.lock 'chalk : deps(self) : ocamlfind list'
  ```
