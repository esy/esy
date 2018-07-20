#!/bin/bash

if [ "$(uname)" = "Darwin" ]; then
  skipTest "disable on macOS because of intermitent failure on Travis"
fi

doTest () {
  initFixture ./fixtures/symlink-workflow

  cd ./app || exit 1

  run esy install

  run esy build
  assertStdout 'esy dep' 'HELLO'
  assertStdout 'esy another-dep' 'HELLO'

  info "modify dep sources"
  printf "#!/bin/bash\necho HELLO_MODIFIED\n" > ../dep/dep
  touch ../dep/dep
  cat ../dep/dep

  run esy build
  assertStdout 'esy dep' 'HELLO_MODIFIED'
}
