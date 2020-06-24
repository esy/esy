---
id: concepts
title: Concepts
---

This serves as a glossary and an overview of concepts used in esy with links to
detailed guide.

## Project Sandbox

A directory with a [manifest](#manifest) (usually `package.json`).

Almost every `esy` command operates in the context of a project sandbox.

## Manifest

A JSON file usually called `package.json` which contains information about esy
package:

- Package name and version.
- Dependency declarations.
- Commands needed to build and install package artifacts.
- Other metadata

#### Support for esy.json

Usually a manifest is represented as `package.json` but to allow `package.json`
to be used exclusively with npm esy allows manifests to be represented as
`esy.json` files. In the case both `package.json` and `esy.json` are present in
the sandbox esy will prefer `esy.json` over `package.json`.

> Note that in case of a published (on npm registry) package esy won't be able
> to access `esy.json` and will only read metadata using npm registry API which
> is populated from `package.json` during publish time.
>
> Maintainers will need to make sure they have crafted a correct `package.json`
> with metadata during publish process.

## Package

A unit of software distribution and the smallest unit which is esy operates on.

## Release mode and Development mode

Any package can be built in two modes - release or development.

During release, a package is built as if it were being consumed by another dependency. Only its `dependencies` are built (not `devDependencies`)

During development mode, a package (most often only the [root](#root-package), is built along with it's `devDependencies` with a special flag set (not important what exactly it is) to signify that a package is being built in development mode. When this flag is set, alternatives to regular configuration (like `buildDev` instead of `build`) are selected in the sandbox.

## Root package

Package at the root of a [sandbox](#sandbox).

## Dependency

Any package that the root package needs to build the sandbox (either during development or releases mode)

## Regular dependency
Dependencies that are required when a package is built in release mode. These are specified in the `dependencies` field.

Packages like `@reason-native/console` are a good example of regular dependencies are these dependencies are required to the build a give root package. They differ from development time dependencies (like `@reason-native/rely`) as we'll see next.


## Development time dependency
Dependencies that are required **only** during development mode are specified in the `devDependencies` (similar to how yarn and npm work)

Good examples of dev-dependency is `@opam/ocaml-lsp-server` or `@reason-native/rely` as it is only required during development of the rot package.

## Build time dependency
Some dependencies are needed during the build. `@opam/dune` and autotools packages are a good examples.

Build time dependencies are meant to be specified as `regular` dependencies as they are needed by the package dependending on it. Build time packages are better compared with runtime packages (instead of dependencies/devDependencies). Once the root package is built, build dependencies are not needed anymore by the root package. Runtime dependencies on the other hand are still needed in the sandbox for the root package to run correctly. `@opam/uchar` is a good example of runtime package. A binary depending on it needs it installed in the sandbox when it is run.

## Peer dependency
Deprecated. We now recommend `resolutions` mechanism over peer dependencies.

## Solution

A result of solving dependencies for a project sandbox.

Cached as `esy.lock` directory in the root of a project.

It is advised to commit this file to a project's repository so that the build
environment is reproducible and doesn't depend on the current state of package
registries (either npm or opam).

## Stores 

Esy maintains three kinds of artifacts - sources, builds and installed artfiacts - in three different locations.

### Sources

Source entries in the esy store are source code files and the recipies that build and install them bundled together. Change any of them, and esy creates a different entry for the source of a package.

If, for instance, build instructions of a package from opam are overridden (and the source files are not necessarily touched), esy places them in a different location.

Conceptually, a source entry in the esy store is both it's source files and it's recipie.

### Build store

Build store is simply location where build artifacts are stored. They can be local to a project or global (so that they can be reused).

Build artifacts (object files, bytecode files etc) stored as separate entries dependending on the instructions that build and install them, environment variables present during its build and of course the sources (source code + recipie).

Change anyone of them, and esy creates a separate entry in the build store.

#### Global build store

Store where the build entries common to multiple projects are stored. This can be considered a a cache too.

By default the global install store can be found at `~/.esy/3/b`

#### Local build store

Store where build entries that are relevant only to a give project are store.

By default the global install store can be found at `<project root>/_esy/default/store/b/<build_id>`

### Install store

Install stores are where final, ready to be consumed, artifacts are stored. The paths (which uniquely identify them) depend on how they are built.

Like build artifacts, install stores can be both local and global.

By default the global install store can be found at `~/.esy/3__../i` and the local one can be found at `<project root>/_esy/default/store/i/<build_id>`

#### Package stage location

As packages are built and installed, they can fail for a lot of reasons. To prevent unusable entries in the install store, packages are first installed to a staging area and only once the steps complete successfully, are they moved to the final store.

## Release

Before a binary executable can be distributed, `esy` can bundle runtime depedendencies together with it and install them alongside. As a proof-of-concept, Esy provides `npm-release` command that creates a npm package that bundle the runtime binaries with a postinstalls cript that correctly installs them and updates the binaries to load the depdendencies from this install path. Check out [`npm-release`](./commands.md#esy-npm-release) to see what that looks like.
