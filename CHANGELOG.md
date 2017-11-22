# CHANGELOG

## 0.0.39

* Use OPAM version ordering when solving dependencies for `@opam/*` packages.

* Fixes to unpackacking OPAM packages' tarballs.

* Make `esy x <anycommand>` command invocaton to perform installation only once.

  That makes subsequent runs of `esy x <anycommand>` to be substantially faster.

* Add `command-exec` executable to ejected root builds. This is used by
  ocaml-language-server package to automatically configure itself to use Esy
  sandboxed environment.

  See freebroccolo/ocaml-language-server#68 for more info.

* Fix builds with dependency graphs with linked packages.

  Previously builds which depend on transient packages were put into a global
  store which is incorrect. Instead those builds are marked as transient too and
  being put into sandbox local store.

## 0.0.38

* Fixes a bug with error in case of build failure which shadowed the actual build
  failure (see #49).

## 0.0.37

* Fixes `0.0.36` release which was broken due to a missing `esx` executable in
  the distribution.

## 0.0.36

* Add `esy x <anycommand>` invocation which allows to execute `<anycommand>` as
  if the project is installed (executables are in `$PATH` and so on).

* New build progress reporter which is consistent with `esy install` command.

* `esy build` command now shows output of build commands on stdout.

* Fix a bug with how build hashes are computed.

* Add experimental `esx` command.

  This is analogue to `esx`. It allows to initialize ad-hoc snadboxes with
  needed packages and run commands right away:

  ```
  % esx -r ocaml -r @opam/reason rtop
  ```

  The command above will init a sandbox with `ocaml` and `@opam/reason` packages
  inside and run `rtop` command (provided by `@opam/reason`). Such sandboxes are
  cached so the next invocations have almost zero overhead.

## 0.0.35

* Add (undocumented yet) `esy build-ls` command.

  This prints the build tree with build info.

* Fix race condition between build process and build ejection (see #40).

* Fix build error when building linked packages (see #36).

* Fix `esy add` to update the correct manifest (see #36).

  Previously it was updating `package.json` even if `esy.json` was present.

* Fix reporting errors with log files residing in sandbox-local stores (see
  #38).

* Shell builder now clears build log before performing the build (see #31).

## 0.0.34

* Fix `esy add` to actually build after the install.

* Run `esy` command wrapper with with `-e` so that we fail on errors.

## 0.0.33

* Make `esy` invocation perform `esy install` and then `esy build`.

  This makes the workflow for starting a development on a project:

  ```
  % git clone project
  % cd project
  % esy
  ```

  Also if you change something in `package.json` you need to run:

  ```
  % esy
  ```

  Pretty simple and consistent with how Yarn behave.

* Make `esy add <pkg>` automatically execute `esy build` after the installation
  of the new package.

  Previously users were required to call `esy build` manually.

* Update OPAM package conversion to include `test`-filtered packages only
  `devDependencies` (see #33 for details).

## 0.0.32

* `esy shell` and `esy <anycommand>` now include dev-time dependencies (declared
  via `devDependencies` in `package.json`) in the environment.

  Examples of dev-time dependencies are `@opam/merlin`, `@opam/ocp-indent`
  packages. Those are only used during development and are not used during the
  build or runtime.

## 0.0.31

* Fix an issue with `esy build/shell/<anycommand>` not to react properly on
  build failure.

* Fix error reporting in ejected builds to report the actual log file contents.

* Use pretty paths to stores without paddings (a lot of underscores).

## 0.0.30

* Command `esy install` now uses `.esyrc` instead of `.yarnrc` for
  configuration.

  If you have `.yarnrc` file in your project which is used only for esy then you
  should do:

  ```
  mv .yarnrc .esyrc
  ```

* Fixed a bug with `esy install` which executed an unrelated `yarn` executable
  in some custom environment setups. Now `esy install` executes only own code.

* Fixed a bug with `esy install` which prevented the command run under `root`
  user. This was uncovered when running `esy install` under docker.

## 0.0.29

* `esy build` command was improved, more specifically:

  * There's new build mode which activates with:

    ```
      "esy": {
        "buildsInSource": "_build"
      }
    ```

    config in `package.json`.

    This mode configures root packages to build into `$cur__root/_build` without
    source relocation. Thus enabling fast incremental builds for projects based
    on jbuilder or ocamlbuild build systems.

    Note that linked packages with `"buildsInSource": "_build"` are still built
    byb relocating sources as it is unsafe to share `$cur__root/_build`
    directory between several sandboxes.

  * Packages now can describe installation commands separately from build
    commands, by using:

    ```
      "esy": {
        "install": ["make install"]
      }
    ```

    config in `package.json`.

    `esy build` invocation now only executes build steps (`"esy.build"` key in
    `package.json`) for the root package build.

  * `esy build` command now ejects a shell script for root build command &
    environment:

    ```
    node_modules/.cache/_esy/bin/build
    node_modules/.cache/_esy/bin/build-env
    ```

    On later invokations `esy build` will reuse ejected shell script to perform
    root project's build process thus enabling invoking builds without spawning
    Node runtime.

    Ejected script invalidates either on any change to `package.json`
    (implemented similarly to how ejected command env invalidates) or to changes
    to linked packages.

  * `esy build <anycommand>` is now supported.

    This works similar to `esy <anycommand>` but invokes `<anycommand>` in build
    environment rather than command environment.

    Currently there are minor changes between build environment and command
    environment but this is going to change soon.

* `esy <anycommand>` and `esy shell` commands implementations changed, more
  specifically:

  * Their environment doesn't include root package's path in `$PATH`,
    `$MAN_PATH` and `$OCAMLPATH`.

  * The location of ejected environment changed from:

    ```
    node_modules/.cache/_esy/command-env
    ```

    to:

    ```
    node_modules/.cache/_esy/bin/command-env
    ```

  * Now `esy build --dependencies-only --silent` is called to eject the command
    env. That means that if command environment is stale (any of `package.json`
    files were modified) then Esy will check if it needs to build dependencies.

* Fix `esy build-shell` command to have exactly the same environment as `esy
  build` operates in.

* Allow to initialize a build shell for any package in a sandbox. Specify
  a package by the path to its source:

      % esy build-shell ./node_modules/@opam/reason

## 0.0.28

* Support for installing packages with only `esy.json` available.

* Add suport for JSON5-encoded `esy.json` manifests and fix edgecases related to
  installation of packages with `esy.json`.

## 0.0.27

* Fix release installation not to ignore "too deep path" error silently.

* Fix a check for a "too deep path" error.

* Esy store version is now set to `3`.

  This is made so the Esy prefix can be 4 chars longer. This makes a difference
  for release installation locations as thise can be 4 chars longer too.

* Change the name of the direction with esy store inside esy releases to be `r`.

  The motivation is also to allow longer prefixes for release installation
  locations.

## 0.0.26

* `esy install` command now supports same arguments as `yarn install`

* Added `esy b` and `esy i` shortcuts for `esy build` and `esy install`
  correspondingly.

* Fix `esy add` command invocation.

  Previously it failed to resolve opam packages for patterns without
  constraints:

      % esy add @opam/reason

  Now it works correctly.

* Expose installation cache management via `esy install-cache` command.

  This works similar to `yarn cache` and in fact is based on it.

* Fix `esy import-opam` to produce `package.json` with dependencies on OCaml
  compiler published on npm registry.

## 0.0.25

* Support for `esy.json`.

  Now if a project (or any dependency) has `esy.json` file then it will take
  precedence over `package.json`.

  This allow to use the same project both as a regular npm-compatible project
  and an esy-compatible project.

* Change lockfile filename to be `esy.lock`.

  This is a soft breaking change. So it is advised to manually rename
  `yarn.lock` to `esy.lock` within Esy projects to keep the lockfile.

## 0.0.24

* `esy install` was improved to handle opam converted package more inline with
  the regular npm packages.

  For example offline mirror feature of Yarn is now fully supported for opam
  converted packages as well.

* `command-env` bash scripts was generated with an incorrect default value for
  a global store path.

## 0.0.23

* Fixes `0.0.22` failure on Linux due to incorrectly computed store path
  padding.

## 0.0.22

* Packages converted from opam now depend on `@esy-ocaml/esy-installer` and
  `@esy-ocaml/substs` packages from npm registry rather than on packages on
  github.

## 0.0.21

* Add `esy config` command.

  `esy config ls` prints esy configuration values

  `esy config get KEY` prints esy configuration value for a specific key

  Example:

  ```
  % esy config get store-path
  % esy config get sandbox-path
  ```

## 0.0.20

* Packages produced by `esy release` command now can be installed with Yarn.

## 0.0.19

* `@opam-alpha/*` namespaces for opam-converted packages is renamed to `@opam/*`
  namespace.

  This is a major breaking change and means that you need to fix your
  dependencies in `package.json` to use `@opam/*`:

      {
        "dependencies": {
          "@opam/reason": "*"
        }
      }

* Symlinks to install and build trees inside stores for a top level package now
  are called now `_esyinstall` and `_esybuild` correspondingly.

  This is not to clash with jbuilder and ocamlbuild which build into `_build` by
  default. See #4.

## 0.0.18

* Prioritize root's `bin/` and `lib/` in `$PATH` and `$OCAMLPATH`.

  Root's binaries and ocamlfind libs should take precedence over deps.

## 0.0.17

* Expose `$cur__lib` as part of the `$OCAMLPATH` in command env.

  That means `esy <anycommand>` will make installed ocamlfind artefacts visible
  for `<anycommand>`.

## 0.0.16

* Make `esy release` not require dependency on Esy:

  * For "dev"-releases we make them install the same version of Esy which was
    used for producing the release.

  * For "bin"-releases and "pack"-releases we don't need Esy installation at
    all.

* Command line interface improvements:

  * Add `esy version` command, same as `esy -v/--version`.

  * Add `esy help` command, same as `esy -h/--help`.

  * Fix `esy version` to print the version of the package but not the version of
    Esy specification.

  * Fix `esy release` invocation (with no arguments) to forward to the JS
    implementation.

* Fix `esy release` to handle releases with commands of the same name as the
  project itself.

  Previously such commands were shadowed by the sandbox entry point script. Now
  we generate sandbox entry point scripts as `<proejctname>-esy-sandbox`, for
  example `reason-cli-esy-sandbox`.

## 0.0.15

* Make `esy build` exit with process return code `1` in case of failures.

  Not sure how I missed that!

* More resilence when crteating symlinks for top level package from store
  (`_build` and `_install`).

  Previously we were seeing failures if for example there's `_build` directory
  created by the build process itself.

* Fix ejected builds to ignore `node_modules`, `_build`, `_install` and
  `_release` directories when copying sources over to `$cur__target_dir`
  directory for build.

* Fix `esy build` command to ignore `_build`, `_install` and
  `_release` directories when copying sources over to `$cur__target_dir`
  directory for build.

## 0.0.14

* Fix `esy install` to work on Node 4.x.

* Do not copy `node_modules`, `_build`, `_install`, `_release` directories over
  to `$cur__target_dir` for in-source builds. That means mich faster builds for
  top level packages.

* Defer creating `_build` symlink to `$cur__target_dir` for top level packages.

  That prevented `jbuilder` to work for top level builds.

## 0.0.13

* Generate readable targets for packages in ejected builds.

  For example:

      make build.sandbox/node_modules/packagename
      make shell.sandbox/node_modules/packagename

* `esy install` command now uses its own cache directory. Previously it used
  Yarn's cache directory.

* `esy import-opam` command now tries to guess the correct version for OCaml
  compiler to add to `"devDependencies"`.

* Fixes to convertation of opam versions into npm's semver versions.

  Handle `v\d.\d.\d` correctly and tags which contain `.`.

## 0.0.12

* Fix invocation of `esy-install` command.

## 0.0.11

* Fix bug with `esy install` which didn't invalidate lockfile entries based on
  OCaml compiler version.

* Allow to override `peerDependencies` for `@opam-alpha/*` packages.

## 0.0.10

* Rename package to `esy`:

  Use `npm install -g esy` to install esy now.

* Pin `@esy-opam/esy-install` package to an exact version.

## 0.0.9

* Make escaping shell commands more robust.

## 0.0.8

* Support for converting opam package from opam repository directly.

  Previously we shipped preconverted metadata for opam packages. Now if you
  request `@opam-alpha/*` package we will convert it directly from opam
  repository.
