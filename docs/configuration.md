---
id: configuration
title: Project Configuration
---

## package.json

esy knows how to build your package and its dependencies by looking at the
`package.json` file at the root of the project.

Because esy needs more information about the project, it extends `package.json`
with the following fields:

- [`esy.build`](#esybuild)
- [`esy.install`](#esyinstall)
- [`esy.buildsInSource`](#esybuildsinsource)
- [`esy.exportedEnv`](#esy.exportedenv)
- [`scripts`](#scripts)

## Specify Build & Install Commands

The crucial pieces of configuration are `esy.build` and `esy.install` keys, they
specify how to build and install built artifacts.

### `esy.build`

Describe how your project's default targets should be built by specifying
a list of commands with `esy.build` config key.

For example, for a [dune](https://dune.readthedocs.io/) based project you'd want to call `dune build`
command.

```
{
  "esy": {
    "build": [
      "dune build",
    ]
  }
}
```

Commands specified in `esy.build` are always executed for the root's project
when user calls `esy build` command.

[esy variable substitution syntax](environment.md#variable-substitution-syntax) can be used to
declare build commands.

### `esy.install`

Describe how you project's built artifacts should be installed by specifying a
list of commands with `esy.install` config key.

```
{
  "esy": {
    "build": [...],
    "install": [
      "esy-installer"
    ]
  }
}
```

For `dune` based projects (and other projects which maintain `.install` file
in opam format) that could be just a single `esy-installer` invokation. The
command is a thin wrapper over `opam-installer` which configures it with esy
defaults.

[esy variable substitution syntax](environment.md#variable-substitution-syntax) can be used to
declare install commands.

## Enforcing Out Of Source Builds

esy requires packages to be built "out of source".

It allows esy to separate source code from built artifacts and thus reuse the
same source code location between several sandboxes.

### `esy.buildsInSource`

Because not every project's build system is designed in a way which allows "out
of source" builds esy has special settings `esy.buildsInSource` which provide
a useful workaround.

There are three modes which are controlled by `esy.buildsInSource` config key:

```
{
  "esy": {
    "build": [...],
    "install": [...],
    "buildsInSource": "_build" | false | true,
  }
}
```

Each mode changes how esy executes [build commands](#esybuild). This is how
those modes work:

- `"_build"`

  Build commands can place artifacts inside the `_build` directory of the
  project's root (`$cur__root/_build` in terms of esy [build
  environment](environment.md#build-environment)).

  This is what [dune](https://dune.readthedocs.io/) or [ocamlbuild](https://github.com/ocaml/ocamlbuild/blob/master/manual/manual.adoc) (in its default configuration)
  users should be using as this matches those build systems' conventions.

- `false` (default if key is omitted)

  Build commands should use `$cur__target_dir` as the build directory.

- `true`

  Projects are allowed to place build artifacts anywhere in their source tree, but not outside of their source tree. Otherwise, esy will defensively copy project's root into `$cur__target_dir` and run build commands from there.

  This is the mode which should be used as the last resort as it degrades
  performance of the builds greatly by placing correctness as a priority.

## Project Specific Commands

### `scripts`

Similar to npm and yarn, esy supports custom project specific commands via
`scripts` section inside `package.json`.

```
"scripts": {
  "build-dev": "esy build dune build --dev",
  "test": "dune runtest",
}
```

The example above defines two new commands.

The command `esy build-dev` is configured to be a shortcut for the following
invocation:

```bash
esy build dune build
```

While the command `esy test` is defined to be a shortcut for:

```bash
esy dune runtest
```

Note that if a command in `scripts` is not prefixed with the `esy` command then it's made to automatically execute inside the [Command Environment](environment.md#Command-Environment).

## Exported Environment

Packages can configure how they contribute to the environment of the packages
which depend on them.

### `esy.exportedEnv`

To add a new environment variable to the esy [build
environment](#build-environment) packages could specify `esy.exportedEnv` config
key:

```
{
  "name": "mylib",
  "esy": {
    ...,
    "exportedEnv": {
      "CAML_LD_LIBRARY_PATH": "#{mylib.lib : $CAML_LD_LIBRARY_PATH}",
      "scope": "global"
    }
  }
}
```

In the example above, the configuration _exports_ (in this specific case it
_re-exports_ it) an environment variable called `$CAML_LD_LIBRARY_PATH` by
appending `$mylib__lib` to its previous value.

Also note the usage of [esy variable substitution
syntax](#variable-substitution-syntax) to define the value of the
`$CAML_LD_LIBRARY_PATH` variable.

## Example: dune (jbuilder)

This is how it looks for a [dune](https://dune.readthedocs.io/) (formely
jbuilder) based project:

```json
{
  "name": "my-dune-project",
  "version": "1.0.0",

  "esy": {
    "build": [
      "dune build"
    ],
    "install": [
      "esy-installer"
    ],
    "buildsInSource": "_build"
  },

  "dependencies": {
    "@opam/dune": "*",
    "@esy-ocaml/esy-installer"
  }
}
```
