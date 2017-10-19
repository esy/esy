# CHANGELOG

## 0.0.12

* Fix invokation of `esy-install` command.

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
