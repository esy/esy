#!/bin/bash

doTest() {
  initFixture ./fixtures/simple-project

  run esy build
  expectStdout "dep" esy build dep
  expectStdout "dep" esy b dep
}
