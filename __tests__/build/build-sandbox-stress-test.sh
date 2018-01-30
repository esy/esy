doTest() {
  initFixture sandbox-stress
  run esy build
  run esy x echo ok
}
