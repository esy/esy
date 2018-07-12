#!/bin/bash

doTest () {
  initFixture ./fixtures/symlink-workflow

  cd ./app || exit 1

  run esy install

  run esy build
  assertStdout 'esy dep' 'HELLO'
  assertStdout 'esy another-dep' 'HELLO'

  info "modify dep sources"
  cat <<EOF > ../dep/dep
  #!/bin/bash

  echo HELLO_MODIFIED
EOF

  run esy build
  assertStdout 'esy dep' 'HELLO_MODIFIED'
}
