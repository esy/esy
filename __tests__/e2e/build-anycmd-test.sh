#!/bin/bash

doTest() {
  initFixture simple-project

  run esy build
  expectStdout "dep" esy build dep
  expectStdout "dep" esy b dep
}
