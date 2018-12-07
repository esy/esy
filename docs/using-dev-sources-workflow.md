---
id: using-repo-sources-workflow
title: Using Unreleased Packages
---

esy allows to use unreleased versions of packages hosted in their development
repositories. This is useful as it allows to try new package versions before
they are released.

## With esy packages

To use an unreleased version of an esy package specify a dependency resolution
in [`resolutions`][cfg-resolutions] field alongside the depedency declaration:

```json
"dependencies": {
  "reason": "*"
},
"resolutions": {
  "reason": "facebook/reason#abcdef"
}
```

This will fetch `reason` package sources from [facebook/reason][] GitHub
repository.

> Why `resolutions`?
>
> This is because in case any other package in the project's sandbox depends on
> `reason` package then it will probably conflict with `facebook/reason`
> declaration (it's most likely others will depend on an already released
> version of reason instead).
>
> Thus we use `resolutions` so that constraint solver is forced to use
> `facebook/reason` declaration in every place `reason` package is required.

Other options are:

- `user/repo#<commit>` will fetch sources from a GitHub's user/repo repository.

  The `<commit>` is mandatory and should point to a specific commit (this will
  be lifted in the future).

  Examples:

  - `facebook/reason#7ada18f`

- `git://example.com/repo.git#<commit>` will fetch sources from a specified git
  repository.

## With opam packages

> This corresponds to opam's `opam pin` workflow.

The same workflow is supported for opam packages.

One can use an unreleased opam packages by specifying its development
repository. The only different is that one should also specify an opam package
name.

Example:

```json
"dependencies": {
  "@opam/lwt": "*",
  "@opam/lwt_ppx": "*"
},
"resolutions": {
  "@opam/lwt": "ocsigen/lwt:lwt.opam#abc342",
}
```

Here we fetch `@opam/lwt` and `@opam/lwt_ppx` packages from the single
`ocsigen/lwt` GitHub repository but refer to different opam manifests `lwt.opam`
and `lwt_ppx.opam` to use corresponding packages.

[cfg-resolutions]: configuration.md#resolutions
[facebook/reason]: https://github.com/facebook/reason
