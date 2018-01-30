doTest () {
  initFixture with-linked-dep-in-source
  run esy build

  # package "dep" should be visible in all envs
  expectStdout "dep" esy dep
  expectStdout "dep" esy b dep
  expectStdout "dep" esy x dep

  expectStdout "with-linked-dep-in-source" esy x with-linked-dep-in-source
}
