doTest () {
  initFixture symlinks-into-dep
  run esy build

  # package "subdep" should be visible in all envs
  expectStdout "subdep" esy subdep
  expectStdout "subdep" esy b subdep
  expectStdout "subdep" esy x subdep

  # same for package "dep" but it should reuse the impl of "subdep"
  expectStdout "subdep" esy dep
  expectStdout "subdep" esy b dep
  expectStdout "subdep" esy x dep

  # and root package links into "dep" which links into "subdep"
  expectStdout "subdep" esy x symlinks-into-dep

  ls ../esy/3/i
  # check that link is here
  storeTarget=$(readlink ../esy/3/i/dep-1.0.0-*/bin/dep)
  if [[ "$storeTarget" != $ESY__PREFIX* ]]; then
    failwith "invalid symlink target: $storeTarget"
  fi

  # export build from store
  run esy export-build ../esy/3/i/dep-1.0.0-*
  cd _export
  run tar xzf dep-1.0.0-*.tar.gz
  cd ../

  # check symlink target for exported build
  exportedTarget=$(readlink _export/dep-1.0.0-*/bin/dep)
  if [[ "$exportedTarget" != ________* ]]; then
    failwith "invalid symlink target: $exportedTarget"
  fi

  # drop & import
  run rm -rf ../esy/3/i/dep-1.0.0
  run esy import-build ./_export/dep-1.0.0-*.tar.gz

  # check symlink target for imported build
  importedTarget=$(readlink ../esy/3/i/dep-1.0.0-*/bin/dep)
  if [[ "$importedTarget" != $ESY__PREFIX* ]]; then
    failwith "invalid symlink target: $exportedTarget"
  fi
}
