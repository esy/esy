# CHANGELOG

## 0.1.3 @ preview

  * Do not run `esy-build-package` just to check if linked deps are changed, do
    it in the same process — this is faster.

  * Fixes to parsing of `"esy.build"` and `"esy.install"` commands.

  * Better error reporting for parsing commands and environment declarations.

  * Show output for the root package build.

## 0.1.2 @ preview

  * Make things faster by adding caching to sandbox metadata.

  * Build devDependencies in parallel with the root package.

  * Fix a bug with `esy build <anycmd>`, `esy <anycmd>`, `esy build-shell` not
    checking if deps are built before starting.

  * Restrict build concurrency by the number of CPU cores available.

  * Fix various bugs: fd leaks, not flushing output channels and so on.

## 0.1.1 @ preview

  * Fix a bug with how esy constructed command-env — the external `$PATH` was
    taking a precedence over sandboxed `$PATH`.

## 0.1.0 @ preview

  * Release new esy core re-implementation in Reason/OCaml.

    A lot of code was replaced and rewritten. This is why we release it under
    `preview` npm tag and not even `next`. Though `esy@preview` already can
    support the workflow of building itself.

## 0.0.68 @ latest

  * Pin dependency to `@esy-ocaml/ocamlrun` package.

## 0.0.67

  * Broken release

## 0.0.66

* Report progress on console even if no tty is available.

  This keeps CI updated and prevent it from timing out thinking builds are stale
  while they are not.

## 0.0.65

* `esy install` now tries to fetch `@opam/*` packages from OPAM archive.

  This is made so esy is less dependent on tarballs hosted on author's servers.

  This only happens if there's no override specified in
  esy-ocaml/esy-opam-override repository.

* Build locks are more granular now and don't require `@esy-ocaml/flock` package
  which was fragile on some systems.

## 0.0.64

* Fix a bug with error reporting in 0.0.63.

## 0.0.63

* New command `esy create` to initialize new esy projects from templates.
  Implemented by @rauanmayemir.

* Source modification check for linked packages is now much faster as it is
  implemented in OCaml.

* New command `esy build-plan [dep]` which prints build task on stdout. Build
  task is a JSON data structure which holds all info needed to build the package
  (environment, commands, ...).

* New command `esy build-package` which builds build tasks produced with `esy
  build-plan` command:

  ```
  % esy build-plan > ./build.json
  % esy build-package build -B ./build.json
  ```

  or directly via stdout:

  ```
  % esy build-plan | esy build-package build -B -
  ```

  Run:

  ```
  % esy build-package --help
  ```

  for more info.

* Build devDependencies in parallel with the root build.

* Remove `dev` and `pack` release and keep only `bin` releases.

* Remove `esy build-eject` command.

## 0.0.62

* Allow to override `@opam/*` packages `url` and `checksum`.

## 0.0.61

* Add `esy ls-modules` command which shows a list of available OCaml modules for
  each of dependency. Implemented by @rauanmayemir.

* Add `$cur__original_root` to build environment which points to the original source
  location of the current package being built.

  Also add `#{self.original_root}` and `#{package_name.original_root}` bindings
  to `#{...}` interpolation expressions.

* Relax sandbox restrictions to allow write `.merlin` files into
  `$cur__original_root` location.

## 0.0.60

* Fix `esy import-build --from <filename>`. See #97 for details.

* Check if `package.json` or `esy.json` is not available in the current
  directory and print nice error message instead of failing with a stacktrace.

## 0.0.59

* Fix `esy build-shell` command to work with `devDependencies`.

* Acquire locks only when invocation is going to perform a build.

* Fixes to how symlink are handled when relocating installation directory
  between between staging and final directory and between stoes (export/import
  and releases).

## 0.0.58

* Esy prefix now can be configured via `.esyrc` by setting `esy-prefix-path`
  property. Example:

  ```
  esy-prefix-path: ./esytstore
  ```

  Esy looks for `.esyrc` in two locations:

  - Sandbox directory: `$ESY__SANDBOX/.esyrc`.
  - User home directory: `$HOME/.esyrc`.

* Fix passing command line arguments to `esy install` and `esy add` commands.

* Fix cloning OPAM and OPAM overrides repositories to respect `--offline` and
  `--prefer-offline` flags. Also make them check if the host is offline and fail
  with a descriptive error instead of hanging.

## 0.0.57

Broken release.

## 0.0.56

* Another bug fix for `#{...}` inside `esy.build` and `esy.install` commands.

## 0.0.55

* Fix bug with scope for `#{...}` inside `esy.build` and `esy.install` commands.

  It was using a `<storePath>/i` instead of `<storePath>/s` for bindings
  pointing to install location. See #89 for details.

## 0.0.54

* Fix sandbox environment to include root package's exported environment.

* Fix for packages which have dot (`.`) symbol in their package names.

## 0.0.53

* Add `esy ls-libs` command which shows a list of available OCaml libraries for
  each of the dependencies. Pass `--all` to see the entire dep tree along with
  OCaml libs. Implemented by @rauanmayemir.

* Command `esy import-build` now supports import builds using `--from/-f <list>`
  option:

  ```
  % esy import-build --from <(find _export -type f)
  ```

  The invocation above will import all builds which reside inside `_export`
  directory.

  That was added to circumvent script startup overhead when importing a large
  number of builds.

* Rename `esy build-ls` command to `esy ls-builds` command so that it is
  consistent with `esy ls-libs`.

* Make variables for the current package also available under `self` scope.

  Instead of using verbose and repetitive `#{package-name.lib}` we can now use
  `#{self.lib}`.

## 0.0.52

* Remove `$cur__target_dir` for builds which are either:

  - Immutable (persisted in the global store). We don't need incremental builds
    there and it's more safer to build from scratch.

  - In-source. We can't enable incremental builds for such builds even if they
    are not being put into global store.

## 0.0.51

* Fix binary releases not to produce single monolithic tarballs.

  So we don't hit GitHub releases limits.

## 0.0.50

* New variable substitution syntax is available for `esy.build`, `esy.install` and
  `esy.exportedEnv`.

  Example:

  ```
  "esy": {
    "exportedEnv": {
      "CAML_LD_LIBRARY_PATH": {
        "val": "#{pkg.lib / 'stublibs' : $CAML_LD_LIBRARY_PATH}"
      }
    }
  }
  ```

  Such variable substitution is performed before the build occurs.

* Automatically export `$CAML_LD_LIBRARY_PATH` variable with the
  `${pkg.stublibs : pkg.lib / 'stublibs' : $CAML_LD_LIBRARY_PATH}`
  value but only case package doesn't have `$CAML_LD_LIBRARY_PATH` in its
  `esy.exportedEnv` config.

* Environment ejected as shell scripts now has nicer format with comments
  indicating from which package the variables are originating from.

## 0.0.49

* Fixes to `esy install` command:

  * OPAM package conversion now convert `depopts` as `optDependencies` which are
    not handled by `esy install` (on purpose) but handled by `esy build`. That
    makes `optDependencies` a direct analogue of OPAM's `depopts`.

  * Fix OPAM package conversion to preevaluate package dependency formulas with
    `mirage-no-xen == true` and `mirage-no-solo5 == true`. This is a temporary
    measure to make a lot of popular packages build. A proper fix pending.

  * Better error reporting in case version constraint wasn't satisfied because of
    OCaml version constraint.

  * Better warning message in case custom resolution doesn't satisfy constraints
    imposed by other packages.

* `esy build` command is now aware of `optDependencies`.

## 0.0.48

* Fixes to `esy install` command:

  * Now it correctly handles OPAM version constraints with `v` prefix (example:
    `v0.9.0`).

    This will invalidate lockfiles which are happen to have records for packages
    with those versions.

  * Handle include files even for packages which doesn't have `url` OPAM meta
    (example: `conf-gmp`).

## 0.0.47

* Fixes to `esy install` command to allow overrides for patches and install
  commands for OPAM packages.

* Fixes to staleness for linked packages which prevent false positives.

## 0.0.46

* Fix `esy import-opam` not to print command header so the output can be piped
  to a `package.json`:

  ```
  % esy import-opam <name> <version> <path/to/opam/file> > package.json
  ```

## 0.0.45

* Fix to locking not to acquire a lock when one is already acquired.

## 0.0.44

* Fix too coarse locking.

  Now we lock only if we can possibly call into Node.

## 0.0.43

* Fix undefined variable reference in `$NODE_ENV`.

## 0.0.42

* Fixes 0.0.41 broken release by adding postinstall.sh script.

## 0.0.41

* Fixes 0.0.40 broken release by adding missing executables.

## 0.0.40

* Add a suite of commands to import and export builds to/from store.

  * `esy export-dependencies` - exports dependencies of the current sandbox.

    Example:

    ```
    % esy export-dependencies
    ```

    This command produces an `_export` directory with a set of gzipped tarballs
    for each of the current project's dependencies.

  * `esy import-dependencies <dir>` - imports dependencies of the current
    sandbox into a store.

    From a directory produced by the `esy export-dependencies` command:

    ```
    % esy import-dependencies ./_export
    ```

    From another Esy store:

    ```
    % esy import-dependencies /path/to/esy/store/i
    ```

* Enable incremental builds for linked dependencies which are configured with:

  ```
  "esy": {
    "buildsInSource": "_build",
    ...
  }
  ```

  (think of jbuilder and ocamlbuild)

* Make `esy x <anycommand>` invocation faster.

  Esy won't perform linked dependencies staleness checks and won't trigger a
  build process anymore. It assumes the project was fully built before.

  For the cases where we want always fresh build artifacts you can combine it
  with `esy b`:

  ```
  % esy b && esy x <anycommand>
  ```

* Do not use symlinks for `link:` dependencies.

  Instead use `_esylink` marker. That prevents linked package's dependencies
  leaking into sandbox.

* Add lock for esy invocations: only single esy command is allowed to run at the
  same time.

  Any other invocaton will be aborted with an error immediately upon startup.

  This ensures there's no corruption of build artifacts for linked dependencies.

* Fix a bug in dependency resolution which caused a wrong version of dependency
  to appear with mixed `esy.json` and `package.json` packages.

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
