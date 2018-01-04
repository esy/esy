# esy

`package.json` workflow for native development with Reason/OCaml.

[![Travis](https://img.shields.io/travis/esy/esy.svg)](https://travis-ci.org/esy/esy)
[![npm](https://img.shields.io/npm/v/esy.svg)](https://www.npmjs.com/package/esy)
[![npm (tag)](https://img.shields.io/npm/v/esy/next.svg)](https://www.npmjs.com/package/esy)

This README serves as a development documentation for esy. For user
documentation refer to [esy.sh][] documentation site.

## Repository structure

- `src` — source code for core esy
- `bin` - bash executable wrappers and utilities
    - `bin/esy` — the entry point of `esy` command
- `esy-build-package` — source code for `esy-build-package` command
- `esy-install` — source code for `esy install`, `esy add` and other yarn-based
  command, this is a submodule which points to `esy/esy-install` repo, a fork of
  `yarn`.
- `merlin` — submodule which points to a development version of Merlin, this is
  used by `esy-build-package` source code.
- `__tests__` — integration tests for `esy`

## Development workflow

To make changes to `esy` and test them locally:

```
% git clone git://github.com/esy/esy.git
% cd esy
% make bootstrap
```

Run:

```
% make
```

to see the description of development workflow.

### Testing Locally

```
% make build-release
% npm remove -g esy
% npm install -g dist
```

Now you may run `esy` commands using your local version of `esy`.


### Running Tests

```
% make test
```

### Issues

Issues are tracked at [esy/esy][].

### Publishing Releases

On a clean branch off of `origin/master`, run:

```
% make bump-patch-version publish
```

to bump the patch version, tag the release in git repository and publish the
tarball on npm.

To publish under custom release tag:

```
% make RELEASE_TAG=next bump-patch-version publish
```

Release tag `next` is used to publish preview releases.

[esy-ocaml-project]: https://github.com/esy-ocaml/esy-ocaml-project
[esy-reason-project]: https://github.com/esy-ocaml/esy-reason-project
[esy/esy]: https://github.com/esy/esy
[esy-ocaml/esy-install]: https://github.com/esy-ocaml/esy-install
[esy-ocaml/esy-opam]: https://github.com/esy-ocaml/esy-opam
[OPAM]: https://opam.ocaml.org
[npm]: https://npmjs.org
[Reason]: https://reasonml.github.io
[OCaml]: https://ocaml.org
[jbuilder]: http://jbuilder.readthedocs.io
[ocamlbuild]: https://github.com/ocaml/ocamlbuild/blob/master/manual/manual.adoc
[PJC]: https://github.com/jordwalke/PackageJsonForCompilers
[esy.sh]: http://esy.sh
