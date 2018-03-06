doTest () {
  initFixture ./fixtures/no-deps-in-source
  run esy build
  expectStdout "no-deps-in-source" esy x no-deps-in-source
}
