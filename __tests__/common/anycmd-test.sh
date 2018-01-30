#!/bin/bash

doTest() {
  initFixture simple-project

  run esy build
  expectStdout "dep" esy dep
}
