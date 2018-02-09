#!/bin/bash

doTest() {
  initFixture ./fixtures/simple-project

  run esy build
  expectStdout "dep" esy build dep
  expectStdout "dep" esy b dep

  checkExitCode () {
    set +e
    "$@"
    local ret="$?"
    set -e
    echo "$ret"
  }
  export -f checkExitCode

  # Make sure exit code is preserved
  expectStdout "1" checkExitCode esy b bash -c 'exit 1'
  expectStdout "7" checkExitCode esy b bash -c 'exit 7'

}
