doTest() {
  initFixture sandbox-stress-in-source
  run esy build
  run esy x echo ok
}
