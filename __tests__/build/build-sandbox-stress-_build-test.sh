doTest () {
  initFixture sandbox-stress-_build
  run esy build
  run esy x echo ok
}
