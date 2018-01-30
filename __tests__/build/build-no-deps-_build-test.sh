doTest() {
  initFixture ./fixtures/no-deps-_build
  run esy build
  run ls
  run ls _build
  run esy x no-deps-_build
  expectStdout "no-deps-_build" esy x no-deps-_build
}
