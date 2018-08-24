#!/usr/bin/env sh

# This script is intended to build `esy` without requiring `esy` itself to be installed.
# For this, we rely on having several OPAM packages installed.

set -u
set -e
set -o pipefail

cp scripts/bootstrap/Makefile.bootstrap Makefile

echo "dune:build esy-build-package"
dune build _build/default/esy-build-package/bin/esyBuildPackageCommand.exe

echo "dune:build esy"
dune build _build/default/esy/bin/esyCommand.exe

echo "make: postinstall.sh"
make _release/bin/esyInstallRelease.js

echo "make: package.json"
make _release/package.json

echo "make: release esy-build-package"
make _release/_build/default/esy-build-package/bin/esyBuildPackageCommand.exe

echo "make: release esy"
make _release/_build/default/esy/bin/esyCommand.exe

echo "make: fastreplacestring"
make _release/bin/fastreplacestring

cd _release
npm install @esy-ocaml/esy-opam

echo "release: link esy-bash"
cd node_modules
rm -rf esy-bash
ln -s ./../../node_modules/esy-bash esy-bash
