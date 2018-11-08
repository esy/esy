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


## Workflow for esy.sh

To make changes to [esy.sh][]:

1. Bootstrap site's dev environment:

  ```
  % make site-bootstrap
  ```

2. Run site locally:

  ```
  % make site-start
  ```

3. When you are happy with the changes:

  ```
  % make site-publish
  ```

## Issues

Issues are tracked at [esy/esy][].

## Publishing Releases

esy is released on npm.

Because esy is written in OCaml/Reason and compiled into a native executable we
need to acquire a set of prebuilt binaries for each supported platform (Windows,
macOS and Linux). We employ CI servers (thanks Azure) to build platform specific
releases.

The release workflow is the following:

1.  Ensure you are on `master` branch and assuming you want to release the
    version currently defined in `package.json` (see step 6.), run

    ```
    % make release-tag
    % git push && git push --tags
    ```

2.  Wait till CI finishes its task and release `@esy-nightly/esy` package.

    You can test it manually.

3.  Run

    ```
    % make release-prepare
    ```

    which downloads the nightly corresponding to the current commit working
    directory is at and "promotes" it to a release. It will create
    `_release/package` directory.

4.  Ensure release inside `_release/package` directory is ok.

    You can `cd _release/package && npm pack && npm install -g ./esy-*.tgz` to test how
    release installs and feels.

5.  Run

    ```
    % make release-publish
    ```

    to upload the release on npm.

    Use

    ```
    % make NPM_RELEASE_TAG=next release-publish
    ```

    To publish release under `next` tag (so users won't get it automatically but
    only explicitly requested).

6.  Bump version in `package.json` to the next patch version.

    We expect next version to be patch version most of the time. In case you
    want to release new minor or major version you need to bump it before the
    reelase.

[hello-ocaml]: https://github.com/esy-ocaml/hello-ocaml
[hello-reason]: https://github.com/esy-ocaml/hello-reason
[esy/esy]: https://github.com/esy/esy
[esy-ocaml/esy-opam]: https://github.com/esy-ocaml/esy-opam
[opam]: https://opam.ocaml.org
[npm]: https://npmjs.org
[reason]: https://reasonml.github.io
[ocaml]: https://ocaml.org
[dune]: http://dune.readthedocs.io
[ocamlbuild]: https://github.com/ocaml/ocamlbuild/blob/master/manual/manual.adoc
[pjc]: https://github.com/jordwalke/PackageJsonForCompilers
[esy.sh]: http://esy.sh
