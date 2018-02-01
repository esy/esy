#!/bin/bash

doTest() {
  initFixture ./fixtures/simple-project

  run esy build
  expectStdout "dep" esy x dep
  expectStdout "dev-dep" esy x dev-dep

  # Make sure we can pass environment from the outside dynamically.
  X=1 expectStdout "1" esy x bash -c 'echo $X'
  X=2 expectStdout "2" esy x bash -c 'echo $X'

  checkExitCode () {
    set +e
    "$@"
    local ret="$?"
    set -e
    echo "$ret"
  }
  export -f checkExitCode

  # Make sure exit code is preserved
  expectStdout "1" checkExitCode esy x bash -c 'exit 1'
  expectStdout "7" checkExitCode esy x bash -c 'exit 7'
}

