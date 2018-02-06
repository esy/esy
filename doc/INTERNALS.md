This document describes how esy main flow works — installing and building a
package and its dependencies.

The outline is:

- `esy install` installs dependencies of the root package into `node_modules`.

- `esy build` works on `node_modules` prepared by the previous step.

Now the more detailed descriptions of each step.

# esy install

1. Check if `esy.lock` is present and is not stale (relative to `package.json`):

  1. `esy.lock` is present and is not stale, proceed to the step 2.

  2. `esy.lock` is not present or is stale, resolve dependencies from
     `package.json` and store resolutions into `esy.lock`.

  3. TODO: describe how we resolve `@opam/*` packages

2. Fetch dependencies from `esy.lock` into installation cache (usually
   `~/.esy/install-cache` but can be configured by setting `$ESY__PREFIX` env
   variable).

  1. TODO: describe how we fetch `@opam/*` packages

3. Populate `node_modules`

  1. Copy packages from installation cache into `node_modules`

  2. Patch `package.json` to store resolution id as `"_resolved"` key.

     This is esy specific and it's not done by yarn (other steps are same with
     yarn unless said otherwise).

     Build process uses this key to construct build identity (resolution id can
     be used like that because it either points on an immutable release version
     or git commit hash). The presence of this field indicates that esy could
     store build in the global store, otherwise it stores the build in the local
     store (under `node_modules/.cache`).

# esy build

- Crawl `node_modules` to construct the package dependency graph

- Compute build environment for each package in the dependency graph and produce
  a build plan. You can see a build plan for a package in a sandbox by running
  the `esy build-plan` command.

  - TODO: describe how this is done, this is specified by pjc-spec

- Feed build plan (serialized as JSON) into `esy-build-package` executable
  which performs the build.

  - TODO: describe in details how build is performed
