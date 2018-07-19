#!/usr/bin/env sh

# This script is intended to build `esy` without requiring `esy` itself to be installed.
# For this, we rely on having several OPAM packages installed.

set -u
set -e
set -o pipefail

cp scripts/bootstrap/Makefile.bootstrap Makefile

echo "jbuilder:build esy-build-package"
jbuilder build --dev _build/default/esy-build-package/bin/esyBuildPackageCommand.exe

echo "jbuilder:build esy"
jbuilder build --dev _build/default/esy/bin/esyCommand.exe

echo "jbuilder:build esyi"
jbuilder build --dev _build/default/esyi/bin/esyi.exe

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

echo "make: release esyi"
make _release/_build/default/esyi/bin/esyi.exe

echo "make: fastreplacestring"
make _release/bin/fastreplacestring

cd _release
npm install @esy-ocaml/esy-opam

echo "release: copy esy-bash"
cp -r ../node_modules/esy-bash node_modules/esy-bash
