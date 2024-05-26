---
id: ci
title: Notes about CI/CD
---

We use [Azure Pipelines](https://dev.azure.com/esy-dev/esy/_build) for
CI/CD. Every successful build from `master` branch is automatically
published to NPM under `@esy-nightly/esy` name. We could,

1. Download the artifact directly from Azure Pipelines, or
2. Download the nightly npm tarball.

### What is EsyVersion.re?

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

Note: you'll need the CI to fetch tags as it clones. By default, for
instance, Github Actions only shallow clones the repository, which
does not fetch tags. Fetching `n` number of commits during the shallow
clone isn't helpful either. This is why, `fetch-depth` is set to `0`
in the Nix Github Actions workflow. (`nix.yml`)

