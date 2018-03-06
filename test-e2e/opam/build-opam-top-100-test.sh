#!/bin/bash

export ESYCOMMAND="$PWD/../../bin/esy"
source "./../../jest-bash-runner/runtime.sh"

doTest () {
  initFixture ./fixtures/opam-top-100

  run esy install
  run esy build
}

doTest
