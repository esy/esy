doTest () {
  initFixture custom-prefix
  unset ESY__PREFIX
  run esy build
  expectStdout "custom-prefix" esy x custom-prefix
}
