---
id: linking-workflow
title: Linking Packages in Development
---

esy allows to link a package in development to a project so that changes to the
linked package are observed in "real time" without the need to keep
re-installing it.

When building a project esy will check & rebuild linked packages on any changes
in their source trees.

## With esy packages

To link a package to the project add a special `link:` resolution to project's
[`resolutions`](cfg-resolutions) field alongside the dependency declaration:

```json
"dependencies": {
  "reason": "*"
},
"resolutions": {
  "reason": "link:../path/to/reason/checkout"
}
```

If you are linking to a folder with many esy packages in it, use the path to the
`json` file that will be use to resolve the dependency, for example:

```json
"dependencies": {
  "refmterr": "*",
},
"resolutions": {
  "refmterr": "link:../reason-native/refmterr.json"
}
```

> Why `resolutions`?
>
> This is because in case any other package in the project's sandbox depends on
> `reason` package then it will certainly conflict with `link:` declaration
> (nothing conforms to `link:` except the same link).
>
> Thus we use `resolutions` so that constraint solver is forced to use `link:`
> declaration in every place `reason` package is required.

## With opam packages

It is also possible to link an opam package, the mechanism is the similar but
you need to specify a path to an `*.opam` file in a `link:` resolution:

```json
"dependencies": {
  "@opam/lwt": "*",
  "@opam/lwt_ppx": "*"
},
"resolutions": {
  "@opam/lwt": "link:../path/to/lwt/checkout/lwt.opam",
  "@opam/lwt_ppx": "link:../path/to/lwt/checkout/lwt_ppx.opam"
}
```

The need to specify an `*.opam` file is because an opam package development repository can contain multiple packages.

[cfg-resolutions]: configuration.md#resolutions
