#!/bin/bash

set -e
set -u
set -o pipefail

#
# link flock executable so we don't have to resolve it at runtime
#

flockBin=$(node -p 'require.resolve("@esy-ocaml/flock/flock")')
rm -f bin/flock
(cd bin && ln -s "$flockBin" flock)

#
# link fastreplacestring.exe executable so we don't have to resolve it at runtime
#

fastreplacestringBin=$(node -p 'require.resolve("fastreplacestring/.bin/fastreplacestring.exe")')
rm -f bin/fastreplacestring.exe
(cd bin && ln -s "$fastreplacestringBin" fastreplacestring.exe)

#
# Spit out config for Esy executables implemented in bash
#

(cd bin && node ./esy.js autoconf > ./esyConfig.sh)
