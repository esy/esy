doTest () {
  initFixture ./fixtures/with-linked-dep-sandbox-env
  run esy build

  # sandbox env should be visible in dep's all envs
  expectStdout "global-sandbox-env-var-in-dep" esy dep
  expectStdout "global-sandbox-env-var-in-dep" esy b dep
  expectStdout "global-sandbox-env-var-in-dep" esy x dep

  expectStdout "with-linked-dep-sandbox-env" esy x with-linked-dep-sandbox-env
}
