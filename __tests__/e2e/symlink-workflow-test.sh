#!/bin/bash

doTest () {
  initFixture symlink-workflow

  cd ./app || exit 1

  run esy install
  run esy add link:../dep

  # just for debug
  cat package.json

  run esy build

  assertStdout 'esy dep' 'HELLO'

  run esy add link:../another-dep
  assertStdout 'esy another-dep' 'HELLO'

  # just for debug
  cat package.json
  ls -la node_modules

  info "modify dep sources"
  cat <<EOF > ../dep/dep
  #!/bin/bash

  echo HELLO_MODIFIED
EOF

  run esy build
  assertStdout 'esy dep' 'HELLO_MODIFIED'
}
