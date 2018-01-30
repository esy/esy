doTest () {
  initFixture ./fixtures/with-linked-dep
  run esy build

  # package "dep" should be visible in all envs
  expectStdout "dep" esy dep
  expectStdout "dep" esy b dep
  expectStdout "dep" esy x dep

  expectStdout "with-linked-dep" esy x with-linked-dep

  info "this SHOULD NOT rebuild dep"
  run esy build

  touch dep/dummy
  info "this SHOULD rebuild dep"
  run esy build
}
