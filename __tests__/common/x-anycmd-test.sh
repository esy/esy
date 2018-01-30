#!/bin/bash

doTest() {
  initFixture simple-project

  run esy build
  expectStdout "dep" esy x dep
  expectStdout "dev-dep" esy x dev-dep
}

