#!/bin/bash

doTest () {
  initFixture ./fixtures/release

  run esy install
  run esy release
  run cd _release

  run npmGlobal pack
  run npmGlobal -g install ./release-*.tgz

  assertStdout "$TEST_NPM_PREFIX/bin/release.exe" RELEASE-HELLO
  assertStdout "$TEST_NPM_PREFIX/bin/release-dep.exe" RELEASE-DEP-HELLO
}
