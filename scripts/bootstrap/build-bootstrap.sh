#!/usr/bin/env sh

cp scripts/bootstrap/Makefile.bootstrap Makefile
make bootstrap
make build-release
