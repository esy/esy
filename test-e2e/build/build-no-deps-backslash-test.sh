# Regression test for slash case hit in PR 232

doTest () {
  initFixture ./fixtures/no-deps
  run esy build
  expectStdout "// no-deps-backslash //" esy x no-deps-backslash
}
