---
id: version-0.3.4-multiple-sandboxes
title: Multiple Project Sandboxes
original_id: multiple-sandboxes
---

Sometimes it is useful to configure multiple sandboxes per project:

- to build a project with a different compiler version
- to try a project with a different set of dependencies installed
- to build a project using differeng settings configured via environment
  variables

It is inconvenient to modify `package.json` and reinstall dependencies each time
you want to work in a different sandbox configuration.

To streamline this esy provides an ability to have multiple sandbox
configurations per project.

## Configure multiple sandboxes

Put `ocaml-4.6.json` file into the project directory.

> `ocaml-4.6` can be any other name you like for your sandbox config:
> - `with-ocaml-4.6.json`
> - `debug-build.json`

`ocaml-4.6.json` file should have the same format as `package.json` but can have
different configuration for `dependencies`, `devDependencies`, `esy.build` or
other fields described in [Project Configuration](configuration.md).

For example:

```json
{
  ...
  "devDependencies": {
    "ocaml": "~4.6.0"
  }
  ...
}
```

To instruct esy to work with `ocaml-4.6.json` sandbox configuration (instead of
default `package.json`) you can use `@ocaml-4.6` sandbox selector:

- Install the dependencies of the `ocaml-4.6` sandbox:

  ```shell
  esy @ocaml-4.6 install
  ```

- Build the `ocaml-4.6` sandbox:

  ```shell
  esy @ocaml-4.6 build
  ```

- Run a command with the `ocaml-4.6` sandbox environment:

  ```shell
  esy @ocaml-4.6 which ocaml
  ```

> Note that sandbox selector `@<sandbox-name>` should be the first argument to
> `esy` command, otherwise it is treated as an option to a subcommand and won't
> have the desired effect.

## Sandbox configuration overrides

When sandbox configurations differ just by few configuration parameters it is
too much boilerplate to copy over all `package.json` fields to a new sandbox
configuration.

It is possible to use sandbox configuration overrides to aleviate the need in
such boilerplate.

Overrides have the following format:

```json
{
  "source": "./package.json",
  "override": {
    <override-fields>
  }
}
```

Where `source` key defines the origin configuration which is being overriden
with the fields from `override` key.

Not everything can be overriden and `<override-fields>` can contain one or more
of the following keys.

### `build`

This replaces [esy.build](configuration.md#esybuild) commands of the origin
sandbox configuration:

```json
"override": {
  "build": "dune build"
}
```

### `install`

This replaces [esy.install](configuration.md#esyinstall) commands of the origin
configuration.

```json
"override": {
  "install": "esy-installer project.install"
}
```

### `exportedEnv`

This replaces [esy.exportedEnv](configuration.md#esyexportedenv) set of exported
environment variables of the origin configuration.

```json
"exportedEnv": {
  "NAME": {"val": "VALUE", "scope": "global"}
}
```

If you need to add to a set of exported environment variables rather than
replace the whole set use `exportedEnvOverride` key instead.

### `exportedEnvOverride`

This overrides [esy.exportedEnv](configuration.md#esyexportedenv) set of exported
environment variables of the origin configuration.

Environment variables specified using this key are being added instead of
replacing the entire set. If a declaration for an environment variable is set to
`null` then the variable is removed from the set.

```json
"exportedEnvOverride": {
  "VAR_TO_ADD": {"val": "VALUE", "scope": "global"},
  "VAR_TO_REMOVE": null
}
```

### `buildEnv`

This replaces [esy.buildEnv](configuration.md#esybuildenv) set of build
environment variables of the origin configuration.

```json
"buildEnv": {
  "NAME": "VALUE"
}
```

If you need to add to a set of build environment variables rather than
replace the whole set use `buildEnvOverride` key instead.

### `buildEnvOverride`

This overrides [esy.buildEnv](configuration.md#esybuildenv) set of build
environment variables of the origin configuration.

Environment variables specified using this key are being added instead of
replacing the entire set. If a declaration for an environment variable is set to
`null` then the variable is removed from the set.

```json
"buildEnvOverride": {
  "VAR_TO_ADD": "VALUE",
  "VAR_TO_REMOVE": null
}
```

### `dependencies`

This overrides [dependencies](configuration.md#dependencies) set of dependency
declaraations of the origin configuration.

```json
"dependencies": {
  "dependency-to-add": "^1.0.0",
  "dependency-to-remove": null
}
```

### `devDependencies`

This overrides [devDependencies](configuration.md#devDependencies) set of dev
dependencies of the origin configuration.

```json
"devDependencies": {
  "dependency-to-add": "^1.0.0",
  "dependency-to-remove": null
}
```

### `resolutions`

This replaces [resolutions](configuration.md#resolutions) set of dependency
resolutions.
