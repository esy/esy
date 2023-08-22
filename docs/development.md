---
id: development
title: Development
---

To make changes to `esy` and test them locally:

```bash
git clone git://github.com/esy/esy.git
cd esy
```

And then,

On Linux/MacOS, run newly built `esy` executable from anywhere like `PATH_TO_REPO/_build/default/bin/esy`.
On Windows, use the cmd wrapper in `PATH_TO_REPO/bin/esy.cmd`. On Windows, esy binary needs [`esy-bash`](https://github.com/esy/esy-bash). `esy` distributed on NPM finds it in the node_modules, but the dev binary finds it via the `ESY__ESY_BASH` variable in the environment.

## Running Tests

1. Fast tests (no internet connection needed)
```sh
yarn jest
```

2. Slow tests (needs internet connection)

```sh
node ./test-e2e-slow/run-slow-tests.js
```

3. Unit tests

```sh
esy b dune runtest
```

## Issues

Issues are tracked at [esy/esy](https://github.com/esy/esy).

## Publishing Releases

`esy` is primarily distributed via NPM (in fact, at the moment, this
is the only distribution channel). To create an NPM tarball, one could
simply run, 

```sh
esy release
```

And the `_release` folder is ready to be installed via NPM. But since
it would contain only one platform's binaries (the machine on which it
was built), we combine builds from multiple platforms on the CI.

We use [Azure Pipelines](https://dev.azure.com/esy-dev/esy/_build) for
CI/CD. Every successful build from `master` branch is automatically
published to NPM under `@esy-nightly/esy` name. We could,

1. Download the artifact directly from Azure Pipelines, or
2. Download the nightly npm tarball.

Once downloaded, one can update the name and version field according
to the release.

Note, that MacOS M1 isn't available on Azure Pipelines yet. So, this
build is included by building it locally, and placing the `_release`
in the `platform-darwin-arm64` folder along side other platforms.

Release tag `next` is used to publish preview releases.

## CI

### EsyVersion.re

We infer esy version with git. A script, `version.sh` is present in
`esy-version/`. This script can output a `let` statement in OCaml or
Reason containing the version.

```sh
sh ./esy-version/version.sh --reason
```

Internally, it uses `git describe --tags`

During development, it's not absolutely necessary to run this script
because `.git/` is always present and Dune is configured extract
it. This, however, is not true for CI as we develop for different
platforms/distribution channels. Case in point, Nix and Docker. Even,
`esy release` copies the source tree (without `.git/`) in isolation to
prepare the npm tarball.

Therefore, on the CI, it's necessary to generate `EsyVersion.re` file
containing the version with the `version.sh` script before running
any of the build commands. You can see this in `build-platform.yml`
right after the `git clone` job.

