#!/bin/bash

skipTest "does not build on CI yet"

initFixture opam-test

run esy install
run esy build
