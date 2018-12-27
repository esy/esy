---
id: what-why
title: What & Why
---

esy is a rapid workflow for developing Reason/OCaml projects. It supports native
packages hosted on opam and npm.


## For [npm](https://npmjs.org/) users

esy lets you manage native Reason/OCaml projects with a familiar npm-like workflow:

* Declare dependencies in `package.json`.

* Run the `esy` command within your project to download/build dependencies.

* Share and consume individual Reason/OCaml package sources on the npm registry or Github.

* Access packages published on [opam](https://opam.ocaml.org/) (a package
  registry for OCaml) via `@opam` npm scope (for example `@opam/lwt` to pull
  `lwt` library from opam).

* Easily bundle your project into a self contained, prebuilt binary package and share it
  on npm. These can be installed by anyone using plain npm.

## For [opam](https://opam.ocaml.org/) users

esy provides a fast and powerful workflow for local development of opam packages without
requiring "switches". Opam packages are still accessable, and you can publish
your packages to opam repository.

* Manages OCaml compilers and dependencies on a per project basis.

* Isolates each package environment by exposing only those packages which are
  defined as dependencies.

* Fast parallel builds which are aggressively cached (even across different
  projects).

* Keeps the ability to use packages published on opam repository.

## In depth

* Project metadata is managed inside `package.json`.

* Parallel builds.

* Clean environment builds for reproducibility.

* Global build cache automatically shared across all projects — initializing new
  projects is often cheap.

* File system checks to prevent builds from mutating locations they don't
  own.

* Solves environment variable pain. Native toolchains rely heavily on environment
  variables, and `esy` makes them behave predictably, and usually even gets them
  out of your way entirely.

* Allows symlink style workflows for local development using `link:` dependencies.
  Allows you to work on several projects locally, automatically rebuilding any
  linked dependencies that have changed. There is no need to first register a package
  as "linkable".

* Run commands in project environment quickly `esy <anycommand>`.
