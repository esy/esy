#!/bin/bash

doTest() {
  initFixture ./fixtures/simple-project

  run esy build
  expectStdout "dep" esy x dep
  expectStdout "dev-dep" esy x dev-dep
}

