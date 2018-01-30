doTest() {
  initFixture errorneous-build
  runAndExpectFailure esy build
}
