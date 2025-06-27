---
id: how-it-works
title: How esy works
---

This document describes esy internals.

## Overview

Almost every esy command operates in context of a [project
sandbox](concepts.md#sandbox) which is defined by a sandbox
[manifest](concepts.md#manifest) (usually `package.json` but `esy.json` is also
supported).

## Pipeline

The typical pipeline from having a clean checkout of an esy project to the
point where all artifacts are built consists of the following steps:

- **Solve Dependencies**

  Produces `esy.lock` solution lock out of `package.json`.  This step is
  optional as `esy.lock` can be already present in a fresh checkout.

- **Fetch Dependencies**

  Ensures all packages mentioned in `esy.lock` is in the [Global
  Installation Cache](#global-installation-cache).

- **Crawl Package Graph**

  Crawls the sandbox's lockfile and linked packages and read them into
  `BuildManifest.t`.

- **Produce Task Graph**

  Folds over the `BuildManifest.t` and produces the `Plan.Task.t` structures.

- **Build Task Graph**

  For each `Plan.Task.t` exeute build commands in the corresponding environment
  using `esy-build-package` command.

### Solve Dependencies

This step produces a [solution](concepts.md#solution) out of dependency
declarations found in a project's root [manifest](concepts.md#manifest) and all
transitively dependent packages' manifests.

First, a package universe (a transitive closure of all dependencies' versions)
is constructed by consulting package registries (npm and opam currently) and
other sources (remote URLs, local paths and various git repositories hostings).

The constructed package universe is then encoded as [CUDF](concepts.md#CUDF) and
is fed to a CUDF solver (provided by the `esy-solve-cudf` npm package
which uses [mccs][] solver underneath).

The result of the solver is then decoded and serialized on disk as `esy.lock`.
It is advised to commit this file to version control as it captures the current
state of the project's dependencies. This allows us to reproduce the
exact same environment anywhere.

[mccs]: http://www.i3s.unice.fr/~cpjm/misc/mccs.html

Modules of interest:

- `esyi/Universe`
- `esyi/Resolver`
- `esyi/Solver`
- `esyi/Solution`

### Fetch Dependencies

This step consumes a [solution](concepts.md#solution) produced by the previous
[Solve Dependencies](#solve-dependencies) step and ensures that all packages
mentioned in the solution are fetched and cached in the [Global Installation Cache](#global-installation-cache).

How it works:

- Traverse the solution
- For each record of the solution:
  - Fetch source (either a tarball or a git repo or ...)
  - Apply all needed patches
  - Pack as a `*.tgz` and store in a cache

Modules of interest:

- `esyi/Fetch`
- `esyi/Solution`

### Crawl Package Graph

This step crawls the sandbox's lockfile and linked packages and read them into
`BuildManifest.t`.

Node of this graph are package metadata. Edges are instances of dependency
relations between packages. The dependency relations are defined by the following
fields in a package's manifest:

- `"dependencies"`
- `"peerDependencies"` - same as `"dependencies"` from the point of view of `esy`,
  was used by the legacy implementation of `esy install` command to defer
  installing dependencies to the root package.
- `"optDependencies"` - this models optional dependencies (if they are installed
  they are used, otherwise - ignored), an analogue to opam's `depopts` which are
  being discouraged now.

Modules of interest:

- `esy/Plan`
- `esy/BuildManifest`

### Produce Task Graph

This step consumes `BuildManifest.t` structures and produces `Plan.Task.t`
structures.

The resulted graph is topologically isomorphic to the original
`Solution.Package.t` graph but contains much more information about the build
process for each of the packages in a sandbox:

- A list of ready to execute commands
- An environment which is needed to execute build commands

Modules of interest:

- `esy/Plan`

### Build Task Graph

After `Task.t` is constructed, it's time to build it.

Each `Task.t` is serialized into a JSON format called [Build
Plan](concepts.md#build-plan) which is then used to invoke the `esy-build-package`
executable.

Modules of interest:

- `esy/Build`
- `esy/PackageBuilder`
- `esy-build-package/Builder`

## Caches

There are multiple levels of caches used by esy.

### Global Installation Cache

This cache stores sources of concrete package versions. It can be cleaned with
the `esy cleanup` command. See `esy cleanup --help` for details. This was
previously known as `esy gc`.

#### Location & Structure

The default location for the cache is `~/.esy/esyi/tarballs` and can be
indirectly controlled by the `--cache-path` option of `esyi` executable.

```bash
% tree ~/.esy/source/i
├── esy-installer__0.0.0.tgz
└── substs__0.0.1.tgz
...
```

#### Cache Key

The cache key used for the cache consists of:

- Package name
- Package version
- Package source (needed if package was fetched not from a registry but a git
  repository or other source)
- A hash of all contents of patches and additional files (if those are defined
  for the package, currently used by the opam overrides infra).

### Global Build Store

This cache stores built artifacts of esy packages and related metadata.

#### Location & Structure

The default location for the cache is `~/.esy/3<prefix>` and can be
indirectly controlled by the `--store-path` option of `esy` executable.

The `<prefix>` part of the path consists of a number of underscore characters
`_` which pads the store path so that the length of the path to the `ocamlrun`
executable in the store is exactly 128 characters.

> The number 128 comes from the fact that on some systems a path mentioned in a
> shebang line (first line of executable which starts with `#!`) is limited to
> 128 characters. Thus the current limit ensure that OCaml bytecode executables
> can be run from the store.
> Note, however, that global build store doesn't need the underscores. With large source trees,
> artifacts get created at very deep paths, and this can cause failures on Windows.
> This is why we eventually shortened build paths to just `~/.esy/3/b` in [PR#969](https://github.com/esy/esy/pull/969)

The padding is needed to allow relocating built artifacts between stores.

The cache looks like:

```bash
% tree ~/.esy/4_*
├── b
│   ├── ocaml-4.6.1-4f6b0960
│   ├── ocaml-4.6.1-4f6b0960.info
│   ├── ocaml-4.6.1-4f6b0960.log
│   ...
├── i
│   ├── ocaml-4.6.1-4f6b0960
│   ...
└── s
```

Where

- `b/<key>` is a directory which is used as a build root for a corresponding
  package.
- `b/<key>.log` is log file for the build process of a package which corresponds
  to the `<key>`.
- `b/<key>.info` contains information about the corresponding build process such
  timer ellapsed and so on.
- `s/<key>` is a stage directory for built artifact installation (packages
  install their own artifacts there and then esy moves `s/<key>` to `i/<key>` so
  that the changes to the store are executed atomically.
- `i/<key>` is an installation directory, this is the directory which hosts
  built artifacts of the package which corresponds to the `<key>`.


#### Cache Key

The cache key used for the cache consists of:

- Package name
- Package version
- Hash of all build/install commands and other esy specific metadata from a
  package manifest
- Hash of all dependencies' cache keys

### Local Build Store

Local Build Store follows exactly the same layout and cache key as the Global
Build Store but it is local to a sandbox and located at
`<sandboxPath>/_esy/default/store`.

It is used to store artifacts of packages which don't have a stable build
identity (unreleased software which changes often and doesn't warrant sorting
its artifacts in a Global Build Store).

### Local Sandbox Cache

Local Sandbox Cache stores a computed package and build task graph. It is
located at `<sandboxPath>/_esy/default/cache/sandbox-<hash>`, where `<hash>`
is a hash of:

- Store Path
- Sandbox Path
- Local Store Path
- Version of esy

The cache is stored in a format readable by the OCaml [Marshal][] module.

> Reading the cache file with a version of esy which has different
> `SandboxInfo.t` layout than the one with which the cache was produced with
> usually results in a Segmentation Fault.

[Marshal]: https://caml.inria.fr/pub/docs/manual-ocaml/libref/Marshal.html
