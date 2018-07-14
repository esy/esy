#!/bin/bash

doTest () {
  initFixture ./fixtures/symlink-workflow

  cd ./app || exit 1

  run esy install

  run esy build
  assertStdout 'esy dep' 'HELLO'
  assertStdout 'esy another-dep' 'HELLO'

  info "modify dep sources"
  run stat -f "%m" ../dep/dep
  printf "#!/bin/bash\necho HELLO_MODIFIED\n" > ../dep/dep
  run stat -f "%m" ../dep/dep
  cat ../dep/dep

  run esy build
  assertStdout 'esy dep' 'HELLO_MODIFIED'
}
