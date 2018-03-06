#!/bin/bash

doTest() {
  initFixture ./fixtures/simple-project

  run esy build

  expectStdout "dep" esy dep
  expectStdout "dev-dep" esy dev-dep

  # Make sure we can pass environment from the outside dynamically.
  X=1 expectStdout "1" esy bash -c 'echo $X'
  X=2 expectStdout "2" esy bash -c 'echo $X'

  checkExitCode () {
    set +e
    "$@"
    local ret="$?"
    set -e
    echo "$ret"
  }
  export -f checkExitCode

  # Make sure exit code is preserved
  expectStdout "1" checkExitCode esy bash -c 'exit 1'
  expectStdout "7" checkExitCode esy bash -c 'exit 7'

}
