doTest() {
  initFixture ./fixtures/sandbox-stress
  run esy build
  run esy x echo ok
}
