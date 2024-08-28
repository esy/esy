---
id: ocaml-compiler
title: Using the OCaml compiler
authors: [prometheansacrifice]
---

## Package

`esy` installs the OCaml compiler packaged for NPM. While, as a user,
this shouldn't affect your workflow, here are the reasons why esy
doesn't use the compiler packages from Opam repository.

1. When esy project was started, the compiler wasn't available on OPAM
2. esy doesn't use the [compiler variants layout](https://discuss.ocaml.org/t/experimental-new-layout-for-the-ocaml-variants-packages-in-opam-repository/6779)
3. Makes it easy to use the solver.


## Version

Since the package is hosted on NPM, it's also necessary to use semver
to specify the compiler version. *We recommend that users specify only
the major version to easily get the patch and minor releases*

Example: `4.x`, `5.x`, `5.1.x`

We advise against specifying the full version (eg: `4.14.0`) as
patches released by wont be seen by the solver. 

## Compiler variants

To install variants of the compiler like `flambda`, `musl-static` etc,
specify the semver tag.

```json
{
  "ocaml": "4.10.1002-musl.static.flambda",
}
```

**Note that the compiler doesn't need patches to work with esy**
