doTest () {
  initFixture simple-project

  unset ESY__PREFIX

  rm -rf /tmp/custom-esy-prefix
  echo 'esy-prefix-path: "/private/tmp/custom-esy-prefix"' > ./.esyrc
  export OCAMLRUNPARAM=b
  run esy build
  expectStdout "dep" esy dep
  run esy which dep | grep "/private/tmp/custom-esy-prefix" || \
    (echo "Not inside the configured prefix" && exit 1)
}
