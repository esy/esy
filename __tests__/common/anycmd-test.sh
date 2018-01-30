#!/bin/bash

doTest() {
  initFixture ./fixtures/simple-project

  run esy build
  expectStdout "dep" esy dep
}
