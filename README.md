# esy

`package.json` workflow for native development with Reason/OCaml.

[![AppVeyor](https://ci.appveyor.com/api/projects/status/0x1mwqeblcgpqyc0/branch/master?svg=true)](https://ci.appveyor.com/project/esy/esy/branch/master)
[![Travis](https://travis-ci.org/esy/esy.svg?branch=master)](https://travis-ci.org/esy/esy)
[![npm](https://img.shields.io/npm/v/esy.svg)](https://www.npmjs.com/package/esy)
[![npm (tag)](https://img.shields.io/npm/v/esy/next.svg)](https://www.npmjs.com/package/esy)

This README serves as a development documentation for esy. For user
documentation refer to [esy.sh][] documentation site.

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Repository structure](#repository-structure)
- [Workflow](#workflow)
  - [Testing Locally](#testing-locally)
  - [Running Tests](#running-tests)
  - [Branches](#branches)
  - [Issues](#issues)
  - [Publishing Releases](#publishing-releases)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Repository structure

The following snippet lists esy repository structured (omitting irrelevant or
obvious items) with further explanations:

    ├── CHANGELOG.md
    ├── LICENSE
    ├── README.md
    │
    ├── Makefile
    │   Common tasks and workflows for esy development.
    │
    ├── bin
    │
    ├── docs
    │   esy end user documentation in markdown format.
    │
    ├── dune
    ├── dune-project
    │
    ├── esy
    │   This dune library implements sandbox builder - a routine which builds
    │   the enture dependency graph and provides other introspection APIs.
    ├── esy/bin
    │   This dune executable implements "esy" command.
    │
    ├── esyi
    │   This dune library implements installer.
    ├── esyi/bin
    │   This dune executable implements "esy install" command.
    │
    ├── esy-build-package
    │   This dune library implements package builder. esy library uses this to
    │   build each package.
    ├── esy-build-package/bin
    │   This dune executable implements "esy-build-package" command.
    │
    ├── esy-installer
    │   Implementation of installation procedure defined with *.install files.
    │   This re-implements opam-installer.
    │
    ├── esy-command-expression
    │   Parser for #{...} syntax used in esy manifests.
    ├── esy-shell-expansion
    │   A simple shell expansion.
    ├── esy-yarn-lockfile
    │   Parser for a subset of yarn lockfile format.
    │
    ├── esy-lib
    │   A collection of utility modules shared between other libraries.
    │
    ├── site
    │   Sources for https://esy.sh
    │
    ├── esy-install
    │   (deprecated) an old "esy install" command implementation which is based
    │   on yarn.
    │
    ├── esy.lock.json
    ├── package.json
    │
    ├── scripts
    ├── test
    │   Unit tests.
    │
    └── test-e2e
        End-to-end test suite.

## Workflow

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

### Running Tests

```
% make test
```

### Branches

There are two branches:

- `master` — the active development, we cut new versions out of there regularly.
- `0.0.x` — maintainance branch for 0.0.x releases.

### Issues

Issues are tracked at [esy/esy][].

### Publishing Releases

esy is released on npm.

Because esy is written in OCaml/Reason and compiled into a native executable we
need to acquire a set of prebuilt binaries. We employ CI servers (thanks Travis
CI) to build platform specific releases.

The release workflow is the following:

1.  Ensure you arre on `master` branch and run

    ```
    % make bump-patch-verson
    % git push && git push --tags
    ```

    (this bumps patch version, use `bump-minor-version` or `bump-major-version`
    correspondingly to bump either minor or major version of esy)

2.  Wait till CI finishes its task and uploads releases on GitHub,
    check https://github.com/esy/esy/releases for them.

3.  Run

    ```
    % make release
    ```

    Which downloads platform specific releases (which CI uploaded GitHub) and
    produces an npm releases with needed metadata inside `_release` directory.

4.  Ensure release inside `_release` directory is ok.

    You can `cd _release && npm pack && npm install -g ./esy-*.tgz` to test how
    release installs and feels.

5.  Run `cd _release && npm publish` to publish release on npm.

    Release tag `next` is used to publish preview releases.

[hello-ocaml]: https://github.com/esy-ocaml/hello-ocaml
[hello-reason]: https://github.com/esy-ocaml/hello-reason
[esy/esy]: https://github.com/esy/esy
[esy-ocaml/esy-install]: https://github.com/esy-ocaml/esy-install
[esy-ocaml/esy-opam]: https://github.com/esy-ocaml/esy-opam
[opam]: https://opam.ocaml.org
[npm]: https://npmjs.org
[reason]: https://reasonml.github.io
[ocaml]: https://ocaml.org
[dune]: http://dune.readthedocs.io
[ocamlbuild]: https://github.com/ocaml/ocamlbuild/blob/master/manual/manual.adoc
[pjc]: https://github.com/jordwalke/PackageJsonForCompilers
[esy.sh]: http://esy.sh
