#!/bin/bash

doTest() {
  initFixture simple-project

  # Check that `esy build` ejects a command-env which contains deps and devDeps
  # in $PATH.
  run esy build
  expectStdout "dep" \
    bash -c 'source ./node_modules/.cache/_esy/build/bin/command-env && dep'
  expectStdout "dev-dep" \
    bash -c 'source ./node_modules/.cache/_esy/build/bin/command-env && dev-dep'
}

