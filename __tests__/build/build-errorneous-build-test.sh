doTest() {
  initFixture ./fixtures/errorneous-build
  runAndExpectFailure esy build
}
