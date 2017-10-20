# CHANGELOG

## 0.0.14

* Fix `esy install` to work on Node 4.x.

* Do not copy `node_modules`, `_build`, `_install`, `_release` directories over
  to `$cur__target_dir` for in-source builds. That means mich faster builds for
  top level packages.

* Defer creating `_build` symlink to `$cur__target_dir` for top level packages.

  That prevented `jbuilder` to work for top level builds.

## 0.0.13

* Generate readable targets for packages in ejected builds.

  For example:

      make build.sandbox/node_modules/packagename
      make shell.sandbox/node_modules/packagename

* `esy install` command now uses its own cache directory. Previously it used
  Yarn's cache directory.

* `esy import-opam` command now tries to guess the correct version for OCaml
  compiler to add to `"devDependencies"`.

* Fixes to convertation of opam versions into npm's semver versions.

  Handle `v\d.\d.\d` correctly and tags which contain `.`.

## 0.0.12

* Fix invocation of `esy-install` command.

## 0.0.11

* Fix bug with `esy install` which didn't invalidate lockfile entries based on
  OCaml compiler version.

* Allow to override `peerDependencies` for `@opam-alpha/*` packages.

## 0.0.10

* Rename package to `esy`:

  Use `npm install -g esy` to install esy now.

* Pin `@esy-opam/esy-install` package to an exact version.

## 0.0.9

* Make escaping shell commands more robust.

## 0.0.8

* Support for converting opam package from opam repository directly.

  Previously we shipped preconverted metadata for opam packages. Now if you
  request `@opam-alpha/*` package we will convert it directly from opam
  repository.
