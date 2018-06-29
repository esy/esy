#!/usr/bin/env sh

cp scripts/bootstrap/Makefile.bootstrap Makefile

# Not sure why this needs to be run multiple times..
# https://github.com/esy/esy/issues/213
make bootstrap
make bootstrap
make bootstrap

make build-release
