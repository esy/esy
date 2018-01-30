doTest() {
  initFixture ./fixtures/sandbox-stress-in-source
  run esy build
  run esy x echo ok
}
