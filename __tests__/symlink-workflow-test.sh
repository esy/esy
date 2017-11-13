#!/bin/bash

source ./testlib.sh

initFixture symlink-workflow

pushd ./app

run esy install
run esy add link:../dep

# just for debug
cat package.json
ls -la node_modules

run esy build

assert_stdout 'esy dep' 'HELLO'

run esy add link:../another-dep
assert_stdout 'esy another-dep' 'HELLO'

# just for debug
cat package.json
ls -la node_modules

info "modify dep sources"
cat <<EOF > ../dep/dep
#!/bin/bash

echo HELLO_MODIFIED
EOF

run esy build
assert_stdout 'esy dep' 'HELLO_MODIFIED'
