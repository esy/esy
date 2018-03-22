doTest () {
  initFixture ./fixtures/with-linked-dep-sandbox-env
  run esy build

  # sandbox env should be visible in runtime dep's all envs
  expectStdout "global-sandbox-env-var-in-dep" esy dep
  expectStdout "global-sandbox-env-var-in-dep" esy b dep
  expectStdout "global-sandbox-env-var-in-dep" esy x dep

  # sandbox env should not be available in build time dep's envs
  expectStdout "-in-dep2" esy dep2
  expectStdout "-in-dep2" esy b dep2

  # sandbox env should not be available in dev dep's envs
  expectStdout "-in-dep3" esy dep3

  expectStdout "with-linked-dep-sandbox-env" esy x with-linked-dep-sandbox-env
}
