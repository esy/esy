#!/bin/bash

set -e
set -u
set -o pipefail

flockBin=$(node -p 'require.resolve("@esy-ocaml/flock/flock")')
rm -f bin/flock
(cd bin && ln -s "$flockBin" flock)

fastreplacestringBin=$(node -p 'require.resolve("fastreplacestring/.bin/fastreplacestring.exe")')
rm -f bin/fastreplacestring.exe
(cd bin && ln -s "$fastreplacestringBin" fastreplacestring.exe)
