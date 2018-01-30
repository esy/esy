#!/bin/bash

doTest() {
  initFixture simple-project

  # Check that `esy command-env` generates valid envitronmenmt with deps and
  # devdeps in $PATH
  run esy build
  run esy command-env > ./command-env
  expectStdout "dep" bash -c 'source ./command-env && dep'
  expectStdout "dev-dep" bash -c 'source ./command-env && dev-dep'
}
