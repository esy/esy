---
id: release-process
title: Release Process
---

esy is released on npm.

Because esy is written in OCaml/Reason and compiled into a native executable we need to acquire a set of prebuilt binaries for each supported platform (Windows, macOS and Linux). We employ CI servers (thanks Azure) to build platform specific releases. For MacOS M1, however, we don't have a CI runner and build the artifact from a M1 machine and add it to the tarball before uploading to NPM.

The release workflow is the following:

1. After making sure the `master` branch is green, we create a release on Github from the [release page](https://github.com/esy/esy/releases). This triggers the CI which will eventually produce an NPM tarball (called release.zip) on [Azure Pipelines](https://dev.azure.com/esy-dev/esy/_build) containing pre-built binaries for MacOS (Intel), Linux (statically linked) and Windows. All `x86_64`

2. `release.zip` is downloaded

3. Build on a MacOS M1 machine

	a. Fetch all git tags
	
	b. Build the source at the tag being release. [This page](./building-from-source.md) explains how to build esy from source.
	
    c. Run `esy npm-release`
	
	d. Place `_release` inside unzipped `release.zip` folder as: `/platform-darwin-arm64`. The contents of release folder will very likely look like the follow (with the m1 artifacts)
	
```
	.
|-- LICENSE
|-- README.md
|-- bin
|   `-- esy
|-- package.json
|-- platform-darwin
|   |-- LICENSE
|   |-- README.md
|   |-- _export
|   |   `-- esy-b79b29e0.tar.gz
|   |-- bin
|   |   |-- _storePath
|   |   `-- esy
|   |-- esyInstallRelease.js
|   `-- package.json
|-- platform-darwin-arm64
|   |-- LICENSE
|   |-- README.md
|   |-- _export
|   |   `-- esy-f489fcc4.tar.gz
|   |-- bin
|   |   |-- _storePath
|   |   `-- esy
|   |-- esyInstallRelease.js
|   `-- package.json
|-- platform-linux
|   |-- _export
|   |   `-- esy-0c16a771.tar.gz
|   |-- bin
|   |   |-- _storePath
|   |   `-- esy
|   |-- esyInstallRelease.js
|   `-- package.json
|-- platform-windows-x64
|   |-- LICENSE
|   |-- README.md
|   |-- _export
|   |   `-- esy-34889961.tar.gz
|   |-- bin
|   |   |-- _storePath
|   |   `-- esy.exe
|   |-- esyInstallRelease.js
|   `-- package.json
`-- postinstall.js
```

4. Publish the folder to NPM

