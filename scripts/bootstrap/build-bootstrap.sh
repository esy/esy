#!/usr/bin/env sh

# This script is intended to build `esy` without requiring `esy` itself to be installed.
# For this, we rely on having several OPAM packages installed.

set -u
set -e
set -o pipefail

cp scripts/bootstrap/Makefile.bootstrap Makefile

echo "jbuilder:build esy-build-package"
jbuilder build _build/default/esy-build-package/bin/esyBuildPackageCommand.exe

echo "jbuilder: build esy"
jbuilder build _build/default/esy/bin/esyCommand.exe

echo "make: esy-install"
make _release/bin/esy-install.js

echo "make: postinstall.sh"
make _release/bin/esyInstallRelease.js

echo "make: package.json"
make _release/package.json

echo "make: release esy-build-package"
make _release/_build/default/esy-build-package/bin/esyBuildPackageCommand.exe

echo "make: release esy"
make _release/_build/default/esy/bin/esyCommand.exe
