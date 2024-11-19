# esy

`package.json` workflow for native development with Reason/OCaml

[![Build](https://github.com/esy/esy/actions/workflows/release.yml/badge.svg)](https://github.com/esy/esy/actions/workflows/release.yml)

Esy is a package manager for Reason and OCaml centered around the [NPM] workflow. Reason/OCaml are compiled languages and it can be daunting for developers to setup tools and develop a workflow that is intuitive and well documented. Developing apps that are natively compiled are also hard to reproduce and often require additional tooling. Esy tries address these, by offering a familiar `package.json` centered workflow and light-weight sandboxing.

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Repository structure](#repository-structure)
- [Workflow](#workflow)
  - [Testing Locally](#testing-locally)
  - [Running Tests](#running-tests)
  - [Branches](#branches)
  - [Issues](#issues)
  - [Publishing Releases](#publishing-releases)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Installation

Esy is available on NPM.

```sh
npm i -g esy
```

## Documentation

You can find the Esy documentation [on the website](https://esy.sh/). You can also find them under the [docs folder](./docs) of the source tree.

## Contributing

Please refer the documents in [docs/contributing](./docs/contributing). You'll find instructions for building the source, CI setup, release process, esy internal concepts and other documentation to help you get started hacking on esy. You can also find them on the website [under the contributing section](https://esy.sh/docs/contributing/building-from-source)

## Issues

Issues are tracked at [esy/esy][].

## History and motivation

See [`package.json` for compilers](https://github.com/jordwalke/PackageJsonForCompilers)

## Maintenance and Sponsorship

This project was originally authored by [Andrey Popp](https://github.com/andreypopp), and is currently maintained by [ManasJayanth](https://github.com/ManasJayanth). The project is currently not funded and could benefit from generous sponsorships.

[esy/esy]: https://github.com/esy/esy
[NPM]: https://npmjs.org
[esy.sh]: http://esy.sh

