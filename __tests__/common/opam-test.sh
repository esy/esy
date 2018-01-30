#!/bin/bash

skipTest "does not build on CI yet"

doTest () {
  initFixture ./fixtures/opam-test

  run esy install
  run esy build
}
