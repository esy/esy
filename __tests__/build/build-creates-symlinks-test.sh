doTest () {
  initFixture ./fixtures/creates-symlinks
  run esy build

  expectStdout "dep" esy dep
  expectStdout "dep" esy b dep
  expectStdout "dep" esy x dep

  expectStdout "creates-symlinks" esy x creates-symlinks
}
