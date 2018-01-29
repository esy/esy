#!/bin/bash

doTest() {
  initFixture simple-project

  # Check that `esy build-env` generates an environment with deps in $PATH.
  run esy build
  run esy build-env > ./build-env
  expectStdout "dep" bash -c 'source ./build-env && dep'
  runAndExpectFailure bash -c 'source ./build-env && dev-dep'
}
