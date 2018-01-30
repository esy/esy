
doTest () {
  initFixture no-deps
  run esy build
  expectStdout "no-deps" esy x no-deps
}
