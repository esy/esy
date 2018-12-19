---
id: version-0.3.4-opam-workflow
title: Developing opam projects
original_id: opam-workflow
---

> **This feature is experimental**
>
> This feature didn't receive a lot of testing, please report any issues found
> and feature requests.

esy supports developing opam projects directly, the workflow is similar to esy
projects:

```bash
% git clone https://github.com/rgrinberg/ocaml-semver.git
% cd ocaml-semver
% esy install
% esy build
```

`esy install` reads dependencies from all opam files found in a project and
installs them into a `node_modules` directory.

`esy build` performs differently depending on the number of opam files
found in a project directory:

- In case there's a single `*.opam` file found `esy build` will build all
  dependencies and then execute `build` commands found in opam metadata.

- In case there are multiple `*.opam` files found `esy build` will build all
  dependencies and stop. To build the project itself users are supposed to use the
  command which is specified by the project's workflow but run inside the esy's
  build environment. In case of a dune-based project this is usually means:

  ```bash
  % esy b dune build
  ```
