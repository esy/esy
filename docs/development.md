---
id: development
title: Development
---

To make changes to `esy` and test them locally:

```bash
git clone git://github.com/esy/esy.git
cd esy
make bootstrap
```

And then run newly built `esy` executable from anywhere like `PATH_TO_REPO/bin/esy`.

Run:

```bash
make
```

to see the description of development workflow.

## Running Tests

Run all test suites:

```bash
make test
```

## Issues

Issues are tracked at [esy/esy](https://github.com/esy/esy).

## Publishing Releases

On a clean branch off of `origin/master`, run:

```bash
make bump-patch-version publish
```

to bump the patch version, tag the release in git repository and publish the
tarball on npm.

To publish under custom release tag:

```bash
make RELEASE_TAG=next bump-patch-version publish
```

Release tag `next` is used to publish preview releases.
