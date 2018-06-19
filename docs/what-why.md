---
id: what-why
title: What & Why
---

### For npm users

For those familiar with [npm](https://npmjs.org/), esy allows to work with Reason/OCaml projects
within the familiar npm-like workflow:

* Declare dependencies in `package.json`.

* Install and build with `esy install` and `esy build` commands. Dependencies'
  source code end up in `node_modules`.

* Share your work with other developers by publishing on npm registry and/or github.

* Access packages published on [OPAM](https://opam.ocaml.org/) (a package registry for OCaml) via
  `@opam` npm scope (for example `@opam/lwt` to pull `lwt` library from OPAM).

### For OPAM users

For those who familiar with [OPAM](https://opam.ocaml.org/), esy provides a powerful alternative (to
the `opam` tool, OPAM packages are still accessible with Esy):

* Manages OCaml compilers and dependencies on a per project basis.

* Sandboxes project environment by exposing only those packages which are
  defined as dependencies.

* Fast parallel builds which are agressively cached (even across different projects).

* Keeps the ability to use packages published on OPAM repository.

### In depth

* Project metadata is managed inside `package.json`.

* Parallel builds.

* Clean environment builds for reproducibility.

* Global build cache automatically shared across all projects — initializing new
  projects is often cheap.

* File system sandboxing to prevent builds from mutating locations they don't
  own.

* Solves environment variable pain. Native toolchains rely heavily on environment
  variables, and `esy` makes them behave predictably, and usually even gets them
  out of your way entirely.

* Allows symlink workflows for local development (by enforcing out-of-source
  builds). This allows you to work on several projects locally, make changes to
  one project and the projects that depend on it will automatically know they
  need to rebuild themselves.

* Run commands in project environment quickly `esy <anycommand>`.

* Makes sharing of native projects easier than ever by supporting "eject to `Makefile`".

  * Build dependency graph without network access.

  * Build dependency graph where `node` is not installed and where no package
    manager is installed.
