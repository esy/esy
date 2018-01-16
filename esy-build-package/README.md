# esy-build-package

A package builder for [esy][].

## How it works

A single command `esy-build-package` operates on a build description, it allows
to:

- Build a package with `esy-build-package build` command.
- Shell into the build environment with `esy-build-package shell`.
- Execute commands with the build environment with `esy-build-package exec -- <command>`.

### Build description

Build description is a JSON file with the information about a package's build
environment and commands needed to build the package and install its artifacts
to the store.

Example:

```json
{
  "id": "pkg-1.0.0-somehash",
  "name": "pkg",
  "version": "1.0.0",
  "sourceType": "immutable",
  "buildType": "_build",
  "build": [
    ["jbuilder", "build"]
  ],
  "install": [
    ["jbuilder", "install"]
  ],
  "sourcePath": "%sandbox%",
  "env": {
    "cur__name": "pkg",
    "cur__install": "%localStore%/s/name",
    ...
  }
}
```

Usually you get those build description from esy.

Note that some properties are allowed to use `%name%` variables:

- `%sandbox%` — the absolute path to the sandbox.
- `%store%` — the absolute path to the store.
- `%localStore%` — the absolute path to the sandbox-local store.

This is needed to allow build descriptions not to be tied to a concrete host.

Examples:

Build the project using `$PWD/build.json` description:
```
% esy-build-package build
```

Build the project using the specified build description:
```
% esy-build-package build -B build-merlin.json
```

Build description can also be read from stdin (useful for automatically
generated build descriptions):
```
% cat build-merlin.json | esy-build-package build -B -
```

## Requirements

- `rsync` executable

## Development

install `esy`, install dependencies and build:

```
% npm install -g esy
% make install build-dev
```

Then you can test it:

```
% esy x esy-build-package
```

To test with esy:

```
% esy build-plan | /path/to/in/dev/esy-build-package -B -
```

[esy]: http://esy.sh
