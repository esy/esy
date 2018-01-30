doTest () {
  initFixture ./fixtures/with-dev-dep
  run esy build

  # package "dep" should be visible in all envs
  expectStdout "dep" esy dep
  expectStdout "dep" esy b dep
  expectStdout "dep" esy x dep

  # package "dev-dep" should be visible only in command env
  expectStdout "dev-dep" esy dev-dep
  runAndExpectFailure esy b dev-dep
  expectStdout "dev-dep" esy x dev-dep

  expectStdout "with-dev-dep" esy x with-dev-dep
}
