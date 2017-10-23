# CHANGELOG

## NEXT

* Symlinks to install and build trees inside stores for a top level package now
  are called now `_esyinstall` and `_esybuild` correspondingly.

  This is not to clash with jbuilder and ocamlbuild which build into `_build` by
  default. See #4.

## 0.0.18

* Prioritize root's `bin/` and `lib/` in `$PATH` and `$OCAMLPATH`.

  Root's binaries and ocamlfind libs should take precedence over deps.

## 0.0.17

* Expose `$cur__lib` as part of the `$OCAMLPATH` in command env.

  That means `esy <anycommand>` will make installed ocamlfind artefacts visible
  for `<anycommand>`.

## 0.0.16

* Make `esy release` not require dependency on Esy:

  * For "dev"-releases we make them install the same version of Esy which was
    used for producing the release.

  * For "bin"-releases and "pack"-releases we don't need Esy installation at
    all.

* Command line interface improvements:

  * Add `esy version` command, same as `esy -v/--version`.

  * Add `esy help` command, same as `esy -h/--help`.

  * Fix `esy version` to print the version of the package but not the version of
    Esy specification.

  * Fix `esy release` invocation (with no arguments) to forward to the JS
    implementation.

* Fix `esy release` to handle releases with commands of the same name as the
  project itself.

  Previously such commands were shadowed by the sandbox entry point script. Now
  we generate sandbox entry point scripts as `<proejctname>-esy-sandbox`, for
  example `reason-cli-esy-sandbox`.

## 0.0.15

* Make `esy build` exit with process return code `1` in case of failures.

  Not sure how I missed that!

* More resilence when crteating symlinks for top level package from store
  (`_build` and `_install`).

  Previously we were seeing failures if for example there's `_build` directory
  created by the build process itself.

* Fix ejected builds to ignore `node_modules`, `_build`, `_install` and
  `_release` directories when copying sources over to `$cur__target_dir`
  directory for build.

* Fix `esy build` command to ignore `_build`, `_install` and
  `_release` directories when copying sources over to `$cur__target_dir`
  directory for build.

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
