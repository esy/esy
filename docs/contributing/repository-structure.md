---
id: repository-structure
title: Repository Structure
---

The following snippet lists esy repository structured (omitting irrelevant or
obvious items) with further explanations:

```

    ├── CHANGELOG.md
    ├── LICENSE
    ├── README.md
    │
    ├── Makefile (unmaintained)
    │   Common tasks and workflows for esy development.
    │
    ├── bin/esy
    │   symlink (wrapper on Windows) for esy command, used for running tests
    │
    ├── bin/esyInstallRelease.js
    │   postinstall step for npm releases produced with `esy npm-release`
    │   command. This is a built JS file which is developed in a separate flow
    │   inside `esy-install-npm-release/` subdirectory (see below).
    │
    ├── docs
    │   esy end user documentation in markdown format.
    │
    ├── dune
    ├── dune-project
    │
    ├── esy
    │   This dune library implements sandbox builder - a routine which builds
    │   the entire dependency graph and provides other introspection APIs.
    │
    ├── esy/bin
    │   This dune executable implements "esy" command.
    │
    ├── esy-solve
    │   This dune library implements solver.
    │
    ├── esy-fetch
    │   This dune library implements installer - fetching and installing of package sources
    │
    ├── esy-build-package
    │   This dune library implements package builder. esy library uses this to
    │   build each package.
    │
    ├── esy-build-package/bin
    │   This dune executable implements "esy-build-package" command.
    │
    ├── esy-install-npm-release
    │   Sources for `bin/esyInstallRelease.js`.
    │
    ├── esy-command-expression
    │   Parser for #{...} syntax used in esy manifests.
    │
    ├── esy-shell-expansion
    │   A simple shell expansion.
    │
    ├── esy-lib
    │   A collection of utility modules shared between other libraries.
    │
    ├── site
    │   Sources for https://esy.sh
    │
    ├── esy.lock
    │   Lock files. Esy uses itself for development
    │
    ├── package.json
    │   Manifest for yarn to manage NPM dependencies of this project
    │
    ├── scripts
    │
    ├── test
    │   Unit tests.
    │
    ├── test-e2e-slow
    │   End-to-end test suite which takes a significant amount of time since they're 
    │   not mocked or rarely so.
    │   We execute it on CI by placing `@slowtest` token in commit messages.
    │
    └── test-e2e
        End-to-end test suite that dont need the network. Heavily mocked

```
