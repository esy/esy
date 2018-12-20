---
id: version-0.4.7-concepts
title: Concepts
original_id: concepts
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

## Root package

Package at the root of a [sandbox](#sandbox).

## Dependency

## Regular dependency

## Development time dependency

## Build time dependency

## Peer dependency

## Solution

A result of solving dependencies for a project sandbox.

Cached as `esy.lock` directory in the root of a project.

It is advised to commit this file to a project's repository so that the build
environment is reproducible and doesn't depend on the current state of package
registries (either npm or opam).

## Environment

## Build environment

## Command environment

## Test environment

## Package exported environment

## Build store

## Global build store

## Local build store

## Package build location

## Package installation location

## Package stage location

## Release

## OCamlfind

## OCamlfind library
