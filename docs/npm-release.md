---
id: npm-release
title: Building npm Releases
---

Applications developed with esy can have complex dependencies at runtime; not
just code linked statically but also executables, dynamically loaded libraries
and other resources such as images, translations and so on.

This requires a special release process which bundles all those dependencies
together in an end user installable package.

There's `esy npm-release` command which produces an npm package ready to be
published which:

1. Packages project's and all dependencies' pre built artifacts.
2. Exposes a specified set of project's executables as commands available to end
   users.
3. Optionally includes pre built artifacts of project's dependencies.

The very important property of such packages is that only a configured set of
executable is being exposed to an end user, all other executables and libraries
are "private" to the release. That means multiple releases can be installed on a
user's machine with different versions of the same software without interfering
between each other.

## Producing Releases

To configure a release one should add `"esy.release.bin"` configuration field to a
`package.json`:

```json
{
  ...
  "esy": {
    "release": {
      "bin": ["refmt"]
    }
  }
}
```

Such field lists all executable names which must be made available on `$PATH` when
release is installed on a user's machine.

After that configuration is done the only command to run is:

```bash
% esy npm-release
```

Which produces a `_release` directory with a ready to be published npm package
with pre built binaries for the current platform.

> Currently release can only contain an application built for a single platform
> (macOS, Linux or Windows). This restriction will be lifted in the future.

To publish such package to npm:

```bash
% cd _release
% npm publish
```

## Including Dependencies

In some cases project's executables invoke other executables or depend on some
dynamically loaded libraries being available at runtime.

This means that a corresponding project dependency must be bundled as a part of
the project's release.

To configure a set of packages one should set `"esy.release.includePackages"`
configuration field within the project's `package.json` to a list of package
names which should be bundled as part of the release:

```json
{
  ...
  "esy": {
    "release": {
      "bin": ["refmt"],
      "includePackages": [
        "root",
        "@opam/dune",
        "@opam/lwt"
      ]
    }
  }
}
```

A special token `root` is used to refer to the current package.

> We are working on a way to make esy configuration more granular which would
> allow to automatically exclude non-runtime dependencies from releases. We are
> not there yet.

## Relocating Artifacts (Path Rewriting)

Some prebuilt artifacts contain hard coded paths which refer to the location
where the package was built or to their dependencies' locations. Installing such
artifacts on another machine could fail due to different paths.

The notable example is `ocaml` package which can't be simply moved to another
machine or even to a different location within the same machine.

There's a way to "fix" such artifacts by adding an extra step to a release
installation procedure which relocates artifacts by rewriting paths in them.

To enable that one should set `"esy.release.rewritePrefix"` to `true`:

```json
{
  ...
  "esy": {
    "release": {
      "bin": ["refmt"],
      "includePackages": ["root", "ocaml"],
      "rewritePrefix": true
    }
  }
}
```

> **NOTE**
>
> Releases configured with `"esy.release.rewritePrefix": true` cannot be
> installed into deep filesystem locations (the limit is around 108 characters).
