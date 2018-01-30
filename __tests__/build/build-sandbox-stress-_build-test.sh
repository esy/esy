doTest () {
  initFixture ./fixtures/sandbox-stress-_build
  run esy build
  run esy x echo ok
}
