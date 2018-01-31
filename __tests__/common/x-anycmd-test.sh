#!/bin/bash

doTest() {
  initFixture ./fixtures/simple-project

  run esy build
  expectStdout "dep" esy x dep
  expectStdout "dev-dep" esy x dev-dep

  # Make sure we can pass environment from the outside dynamically.
  X=1 expectStdout "1" esy x bash -c 'echo $X'
  X=2 expectStdout "2" esy x bash -c 'echo $X'
}

