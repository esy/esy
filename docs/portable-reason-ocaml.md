---
id: portable-reason-ocaml
title: "Portable Reason/OCaml applications"
---

While the compiler itself is available on a wide range of operating
systems and CPU architectures, the packages on opam aren't necessarily
so. This could be due to a lot of reasons - often, many packages are
just bindings to libraries written in C which may not be written in
portability in mind. This noticed especially on Windows.

Some packages are platform-specific - `eio_main` depends on
platform-specific packages (eg, `eio-posix`, `eio-windows` etc). Opam
files support `available` field which takes expressions, like `os != "win32"`
for example.

However, this can make things a bit difficult - a given project could
result in different lock files on different platforms. Therefore, esy
supports computing lock files for multiple platforms and persisting
them (in one lock file).

By default, esy considers the target set of platforms to be

1. Macos Arm64 and x86_64
2. Linux x86_64
3. Windows x86_64

This can be configured in `package.json`/`esy.json`.

Possible values for `os`: `darwin | linux | cygwin | unix | windows`
Possible values for `cpu`: `x86_32 | x86_64 | ppc32 | ppc64 | arm32 | arm64`

Syntax:
```json
{
  "esy": { ... }
  "available": Array<[<os>, <cpu>]>
}

Example:

```json
{
  "esy": { ... }
  "available": [["darwin", "arm64"], ["linux", "x86_64"]]
}
```

Note that, this feature is a way of saying, "this project is expected
to build correctly on the `available` set of platforms. On the other
platforms, we don't know. It may build, or it may not.". This is
because, platform specific packages are made available in the default
solution, and it's the default solution that gets installed on
unlisted platforms.
