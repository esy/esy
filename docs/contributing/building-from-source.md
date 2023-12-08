---
id: building-from-source
title: Building from source
---

To make changes to `esy` and test them locally:

```
% git clone  --recurse-submodules git://github.com/esy/esy.git
% cd esy # Change to the cloned directory
% esy # install and build dependencies 
% yarn # install NPM dependencies used during development.
```

And then, run newly built `esy` executable from anywhere by adding `PATH_TO_REPO/_build/install/default/bin` to the $PATH during the shell's session. On Windows, append `PATH_TO_REPO/bin` instead, because it contains a smaller wrapper.

```bat
@ECHO off
@SETLOCAL
@SET ESY__ESY_BASH=%~dp0../node_modules/@prometheansacrifice/esy-bash
"%~dp0../_build/install/default/bin/esy.exe" %*
```

On Windows, esy binary needs [`esy-bash`](https://github.com/esy/esy-bash). `esy` distributed on NPM finds it in the node_modules, but the dev binary finds it via the `ESY__ESY_BASH` variable in the environment. This wrapper sets the value of the `ESY__ESY_BASH` to a path in `node_modules` where `esy-bash` is installed by yarn.


### Updating `bin/esyInstallRelease.js`

`bin/esyInstallRelease.js` is developed separately within the `esy-install-npm-release/` directory.

Run:

```
% make bin/esyInstallRelease.js
```

to update the `bin/esyInstallRelease.js` file with the latest changed, don't
forget to commit it.

