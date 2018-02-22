
doTest () {
  initFixture ./fixtures/has-build-time-deps
  run esy build
  expectStdout "dep was built with:
build-time-dep@2.0.0" esy x dep
  expectStdout "has-build-time-deps was built with:
build-time-dep@1.0.0" esy x has-build-time-deps

  expectStdout "build-time-dep@1.0.0" esy b build-time-dep
}
