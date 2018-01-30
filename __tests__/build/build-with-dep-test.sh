doTest () {
  initFixture ./fixtures/with-dep
  run esy build

  # package "dep" should be visible in all envs
  expectStdout "dep" esy dep
  expectStdout "dep" esy b dep
  expectStdout "dep" esy x dep

  expectStdout "with-dep" esy x with-dep
}
