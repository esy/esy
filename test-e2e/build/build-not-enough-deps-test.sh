doTest () {
  initFixture ./fixtures/not-enough-deps

  set +e
  # this should fail as there's not enough deps, collect stderr & stdout
  out=$(esy build 2>&1)
  set -e

  # test that error output has relevant info
  echo "$out" | grep "invalid dependency dep: unable to resolve package"
  echo "$out" | grep "While processing package:"
}
