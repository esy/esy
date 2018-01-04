source ./testlib.sh

initFixture opam-test

run esy install
run esy build
