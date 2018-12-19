---
id: version-0.3.4-release
title: Building Releases
original_id: release
---

Applications developed with esy can have complex dependencies at runtime; not
just code linked statically but also executables, dynamically loaded libraries
and other resources such as images, translations and so on.

This requires a special release process which bundles all those dependencies
together in an end user installable package.

There's `esy release` command which produces an npm package ready to be
published which:

1. Packages project's and all dependencies' pre built artifacts.
2. Exposes a specified set of project's executables as commands available to end
   users.

The very important property of such packages is that only a configured set of
executable is being exposed to an end user, all other executables and libraries
are "private" to the release. That means multiple releases can be installed on a
user's machine with different versions of the same software without interfering
between each other.

## Producing Releases

To configure a release one should add `esy.release.releasedBinaries`
configuration field to a `package.json`:

```json
"esy": {
  "release": {
    "releasedBinaries": [
      "refmt"
    ]
  }
}
```

Such field lists all executable names which must be made available on `$PATH` when
release is installed on a user's machine.

After that configuration is done the only command to run is:

```bash
% esy release
```

Which produces a `_release` directory with a ready to be published npm package
with pre built binaries for the current platform.

> Currently release can only contain an application built for a single platform
> (macOS, Linux or Windows). This restriction will be lifted in the future.

To publish such package to npm:

```bash
% (cd _release && npm publish)
```

## Excluding Dependencies

Not all dependencies of an esy project are needed at runtime. Therefore it makes
sense to exclude them from the release which will make release size smaller.

> We are working on a way to make esy configuration more granular which would
> allow to automatically exclude non-runtime dependencies from releases. We are
> not there yet.

There's `esy.release.deleteFromBinaryRelease` configuration field in
`package.json` which allows to specify a list of glob patterns against artifact
names to be excluded from a release package:

```json
"esy": {
  "release": {
    "releasedBinaries": [ ... ]
    "deleteFromBinaryRelease": [
      "ocaml-*",
      "*jbuilder-*"
    ]
  }
}
```

The configuration above will make sure OCaml toolchain, jbuilder package won't
be present in a release.
