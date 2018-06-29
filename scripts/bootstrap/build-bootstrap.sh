#!/usr/bin/env sh

cp scripts/bootstrap/Makefile.bootstrap Makefile

make bootstrap
make bootstrap

jbuilder build _build/default/esy-build-package/bin/esyBuildPackageCommand.exe
jbuilder build _build/default/esy/bin/esyCommand.exe

make _release/bin/esy-install.js
make _release/bin/esyInstallRelease.js
make _release/scripts/postinstall.sh
make _release/package.json
make _release/_build/default/esy-build-package/bin/esyBuildPackageCommand.exe
make _release/_build/default/esy/bin/esyCommand.exe
