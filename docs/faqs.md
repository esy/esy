---
id: faqs
title: Frequently Asked Questions
---

This is a running list of frequently asked questions (recommendations are very welcome)

## Why doesn't Esy support Dune operations like opam file generation or copying of JS files in the source tree?

TLDR; If you're looking to generate opam files with Dune, use `esy dune build <project opam file>`. For substitution, use `esy dune substs`.

Any build operation is recommended to be run in an isolated sandboxed environment where the sources are considered
immutable. Esy uses sandbox-exec on MacOS to enforce a sandbox (Linux and Windows are pending). It is always recommended 
that build commands are run with `esy b ...` prefix. For this to work, esy assumes that there is no inplace editing of the 
source tree - any in-place editing of sources that take place in the isolated phase makes it hard for esy to bet on immutability
and hence it is not written to handle it well at the moment (hence the cryptic error messages)

Any command that does not generate build artifacts (dune subst, launching lightweight editors etc) are recommended to be run with 
just `esy ...` prefix (We call it the [command environment](https://esy.sh/docs/en/environment.html#command-environment) to distinguish it from [build environment](https://esy.sh/docs/en/environment.html#build-environment))

Esy prefers immutability of sources and built artifacts so that it can provide reproducibility guarantees and other benefits immutability brings.
