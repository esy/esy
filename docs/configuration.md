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
- [`esy.buildDev`](#esybuilddev)
- [`esy.install`](#esyinstall)
- [`esy.buildsInSource`](#esybuildsinsource)
- [`esy.exportedEnv`](#esyexportedenv)
- [`esy.buildEnv`](#esybuildenv)
- [`resolutions`](#resolutions)
- [`scripts`](#scripts)

## Specify Build & Install Commands

The crucial pieces of configuration are `esy.build` and `esy.install` keys, they
specify how to build and install built artifacts.

### `esy.build`

Describe how your package's default targets should be built when package is
being used as a dependency.

For example, for a [dune](https://dune.readthedocs.io/) based package you'd want to call `dune build`
command.

```
{
  "esy": {
    "build": [
      "dune build -p #{self.name}",
    ]
  }
}
```
[esy variable substitution syntax](environment.md#variable-substitution-syntax) can be used to
declare build commands.

### `esy.buildDev`

Describe how your package's default targets should be built when package is
being developed. This is only used for the root package of an esy project.

The main difference with `esy.build` is that commands declared in `esy.buildDev`
have access to `"devDependencies"`.

For example, for a [dune](https://dune.readthedocs.io/) based package you'd want
to call `dune build` command.

```
{
  "esy": {
    "buildDev": [
      "refmterr dune build --root . --only-packages #{self.name}",
    ]
  },
  "devDependencies": {
    "refmterr": "*",
    ...
  }
}
```

Note that we use `refmterr` command which is declared in `"devDependencies"`
section.

[esy variable substitution syntax](environment.md#variable-substitution-syntax)
can be used to declare build commands.

If no `esy.buildDev` is defined then `esy.build` is used instead.

### `esy.install` (optional)

By default `esy` will look for a single `*.install` file in the project root and
will transfer all files mentioned there into `#{self.install}` directory.

This follows the convention of opam and plays well with `dune` (which produces
`*.install` files by default).

But some projects can have special requirements:

- Some have multiple `*.install` files and want to install artifacts only from
  some of them.

- Some might require custom commands to be executed (for example `make install`).

There's `esy.install` config key which allows to specify a set of commands which
should move built artifacts to `#{self.install}` location.

```
{
  "esy": {
    "build": [...],
    "install": [
      "dune install --prefix=#{self.install}"
    ]
  }
}
```

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
      "CAML_LD_LIBRARY_PATH": {
        "val": "#{mylib.lib : $CAML_LD_LIBRARY_PATH}",
        "scope": "global"
      }
    }
  }
}
```

In the example above, the configuration _exports_ (in this specific case it
_re-exports_ it) an environment variable called `$CAML_LD_LIBRARY_PATH` by
appending `$mylib__lib` to its previous value.

Note the usage of [esy variable substitution
syntax](#variable-substitution-syntax) to define the value of the
`$CAML_LD_LIBRARY_PATH` variable.

## Build Environment

Packages can configure their own build environment.

Note that build environment doesn't propagate to dependencies, only current
package's build process can access it.

### `esy.buildEnv`

To add a new environment variable to the build environment of the current
package there's `esy.buildEnv` config key:

```
{
  "name": "mylib",
  "esy": {
    ...,
    "buildEnv": {
      "DUNE_BUILD_DIR": "#{self.target_dir}"
    }
  }
}
```

Note the usage of [esy variable substitution
syntax](#variable-substitution-syntax) to define the value of the
`$DUNE_BUILD_DIR` variable.

## Example: dune (jbuilder)

This is how it looks for a [dune](https://dune.readthedocs.io/) (formely
jbuilder) based project:

```json
{
  "name": "my-dune-project",
  "version": "1.0.0",

  "esy": {
    "build": ["dune build"],
    "buildEnv": {"DUNE_BUILD_DIR": "#{self.target_dir}"}
  },

  "dependencies": {
    "@opam/dune": "*",
    "ocaml": "*"
  }
}
```

## Specify dependencies

### `dependencies`

> This works similar to npm or yarn standard `dependencies` configuration.

To define a set of dependencies of the package specify them in `dependencies`
key inside `package.json`.

```
"dependencies": {
  "refmterr": "^3.1.7",
  "@esy-ocaml/reason": "^3.0.0"
}
```

We refer to the [npm documentation on `dependencies`][npm-dependencies] for the
syntax of possible package constraints.

As esy allows to work with packages hosted on opam repository it extends npm's
standard mechanism with a special handling of `@opam/*` scope:

- Any scoped package `@opam/PKG` refers to an opam packsage `PKG`.

- Any constraint for a scoped package `@opam/PKG` is a constraint against opam
  versions.

### `devDependencies`

> This works similar to npm or yarn standard `devDependencies` configuration.

`devDependencies` works similar to `dependencies` but they are only handled for
the root package and override the constraints found in `dependencies` key.

### `resolutions`

It's sometimes necessary to override the package version determined by the
solver. In such a case, use `resolutions` field in the `package.json`.

```
"resolutions": {
  "@opam/menhir": "20171013"
}
```

This feature works similar to yarn's [Selective dependency resolutions][yarn-resolutions]
but nested patterns (which contain `**` or `*` are not supported).

[yarn-resolutions]: https://yarnpkg.com/lang/en/docs/selective-version-resolutions/

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

However, to ensure forward compatiblity, we encourage a more verbose 
`esy run-script build-dev` and `esy run-script test`. Explicitly specifying
`run-script` prevents clashes with subcommands that we add in future.

Note that if a command in `scripts` is not prefixed with the `esy` command then it's made to automatically execute inside the [Command Environment](environment.md#Command-Environment).

[npm-dependencies]: https://docs.npmjs.com/files/package.json#dependencies
