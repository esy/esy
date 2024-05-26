---
id: environment
title: Environment
---

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Build Environment](#build-environment)
- [Command Environment](#command-environment)
- [Test Environment (exported environment)](#test-environment-exported-environment)
- [Variable substitution syntax](#variable-substitution-syntax)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

For each project esy manages:

* **build environment** — an environment which is used to build the project

* **command environment** — an environment which is used running text editors/IDE
  and for general testing of the built artfiacts

* **test environment** — an environment which includes the current package's
  installation directories and its exported environment. This is useful if you need
  an environment in which the current application appears installed.

Each environment consists of two parts:

1. Base environment provided by esy.
2. Environment exported from the sandbox dependencies. There are several types
   of dependencies esy can understand:

   1. **Regular dependencies** are dependencies which are needed at runtime.
      They are listed in `"dependencies"` key of the `package.json`.

   2. **Development time dependencies** are dependencies which are needed only
      during development. They are listed in `"devDependencies"` key of the
      `package.json`. Examples: `@opam/merlin`, `@opam/ocamlformat` and so on.

   3. **Build time dependencies** (NOT IMPLEMENTED) are dependencies which are
      only needed during the build of the project. Support for those is **not
      implemented** currently. The workaround is to declare such dependencies as
      regular dependencies for the time being.

## Build Environment

The following environment is provided by esy:

* `$SHELL` is set to `env -i /bin/bash --norc --noprofile` so each build is
  executed in an environment clear from user customizations usually found in
  `.profile` or other configuration files.

* `$PATH` contains all regular dependencies' `bin/` directories.

* `$MAN_PATH` contains all regular dependencies' `man/` directories.

* `$OCAMLPATH` contains all regular dependencies' `lib/` directories.

Each regular dependency of the project can also contribute to the environment
through `"esy.exportedEnv"` key in `package.json`. See [Project
Configuration](configuration.md) for details.

## Command Environment

The following environment is provided by esy:

* `$PATH` contains all regular **and development** time dependencies' `bin/`
  directories.

* `$MAN_PATH` contains all regular **and development** dependencies' `man/`
  directories.

* `$OCAMLPATH` contains all regular **and development** dependencies' `lib/`
  directories.

Each regular **and development** dependency of the project can also contribute to the
environment through `"esy.exportedEnv"` key in `package.json`. See [Project
Configuration](configuration.md) for details.

## Test Environment (exported environment)

Some packages need to set environment variables in the environment of the package consuming them. Sometimes, a root package may need to set some variables in the sandbox if the binaries need them.

These environment variables are 'exported' using the `exportedEnv`.

By default, the following environment is provided by esy:

* `$PATH` contains all regular time dependencies' `bin/`
  directories **and project's own** `bin/` directory.

* `$MAN_PATH` contains all regular dependencies' `man/`
  directories **and project's own** `man/` directory.

* `$OCAMLPATH` contains all regular dependencies' `lib/`
  directories  **and project's own** `lib/` directory.

Each regular dependency of the project **and the project itself** can also
contribute to the environment through `"esy.exportedEnv"` key in `package.json`.
See [Project Configuration](configuration.md) for details.

## Variable substitution syntax

Your `package.json`'s `esy` configuration can include "interpolation" regions
written as `#{ }`, where `esy` "variables" can be used which will automatically
be substituted with their corresponding values.

For example, if you have a package named `@company/widget-factory` at version
`1.2.0`, then its `esy.build` field in `package.json` could be specified as:

```json
   "build": "make #{@company/widget-factory.version}",
```

and `esy` will ensure that the build command is interpreted as `"make 1.2.0"`.
In this example the interpolation region includes just one `esy` variable
`@company/widget-factory.version` - which is substituted with the version number
for the `@company/widget-factory` package.

Package specific variables are prefixed with their package name, followed
by an `esy` "property" of that package such as `.version` or `.lib`.

`esy` also provides some other built in variables which help with path and environment
manipulation in a cross platform manner.

**Supported Variable Substitutions:**

Those variables refer to the values defined for the current package:

* `self.name` represents the name of the package
* `self.version` represents the version of the package (as defined in its
  `package.json`)
* `self.root` is the package source root
* `self.target_dir` is the package build directory
* `self.jobs` is the number of processors the build system can used parallely. The name `jobs` is inspired by it counterpart in opam.
* `self.install` is the package installation directory, there are also
  variables defined which refer to common subdirectories of `self.install`:
  * `self.bin`
  * `self.sbin`
  * `self.lib`
  * `self.man`
  * `self.doc`
  * `self.stublibs`
  * `self.toplevel`
  * `self.share`
  * `self.etc`

Note that for packages which have `buildsInSource: true` esy copies sources into `self.target_dir` and therefore values of `self.root` and `self.target_dir` are the same.

You can refer to the values defined for other packages which are direct
dependencies by using the respective `package-name.` prefix. Available variables are the same:

* `package-name.name`
* `package-name.version`
* `package-name.root`
* `package-name.target_dir`
* `package-name.install`
  * `package-name.bin`
  * `package-name.sbin`
  * `package-name.lib`
  * `package-name.man`
  * `package-name.doc`
  * `package-name.stublibs`
  * `package-name.toplevel`
  * `package-name.share`
  * `package-name.etc`

The following constructs are also allowed inside "interpolation" regions:

* `$PATH`, `$cur__bin` : environment variable references
* `'hello'`, `'lib'` : string literals
* `/` : path separator (substituted with the platform's path separator)
* `:` : env var value separator (substituted with platform's env var separator `:`/`;`).

You can join many of these `esy` variables together inside of an interpolation region
by separating the variables with spaces. The entire interpolation region will be substituted
with the concatenation of the space separated `esy` variables.

White space separating the variables are not included in the concatenation, If
you need to insert a literal white space, use `' '` string literal.

Examples:

* `"#{pkg.bin : $PATH}"`

* `"#{pkg.lib / 'stublibs' : $CAML_LD_LIBRARY_PATH}"`
