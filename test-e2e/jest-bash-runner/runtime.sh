#!/bin/bash

set -e
set -o pipefail
set -u

export TEST_ROOT=""
export TEST_PROJECT=""
export TEST_NPM_PREFIX=""

skipTest () {
  local msg="$1"
  echo "$msg"
  exit 66
}

initFixture () {
  set +x

  local fixture="$1"

  TEST_ROOT=$(mktemp -d /tmp/esy.XXXX)
  TEST_PROJECT="$TEST_ROOT/project"
  TEST_BIN="$TEST_ROOT/bin"

  export ESY__PREFIX="$TEST_ROOT/esy"
  export PATH="$TEST_BIN:$PATH"

  # init bin
  mkdir -p "$TEST_BIN"
  ln -s "$ESYCOMMAND" "$TEST_BIN/esy"

  cp -r "$fixture" "$TEST_PROJECT"

  # setup an isolated npm global env
  TEST_NPM_PREFIX="$TEST_ROOT/npm"
  mkdir -p "$TEST_NPM_PREFIX"
  function npmGlobal () {
    npm --prefix "$TEST_NPM_PREFIX" "$@"
  }

  pushd "$TEST_PROJECT"
  set -x
}
export -f initFixture

run () {
  echo "RUNNING:" "$@"
  "$@"
}
export -f run

runAndExpectFailure () {
  echo "RUNNING (expecting failure):" "$@"
  set +e
  "$@"
  local ret="$?"
  set -e
  if [ $ret -eq 0 ]; then
    failwith "expected command to fail"
  fi
}
export -f runAndExpectFailure

failwith () {
  >&2 echo "ERROR: $1"
  exit 1
}
export -f failwith

assertStdout () {
  set +x
  local command="$1"
  local expected="$2"
  local actual
  echo "RUNNING: $command"
  set -x
  actual=$($command)
  set +x
  if [ ! $? -eq 0 ]; then
    failwith "command failed"
  fi
  if [ "$actual" != "$expected" ]; then
    set +x
    echo "EXPECTED: $expected"
    echo "ACTUAL: $actual"
    failwith "assertion failed"
  else
    set -x
    echo "$actual"
  fi
}
export -f assertStdout

expectStdout () {
  set +x
  local expected="$1"
  shift
  local actual
  echo "RUNNING: " "$@"
  set -x
  actual=$("$@")
  set +x
  if [ ! $? -eq 0 ]; then
    failwith "command failed"
  fi
  if [ "$actual" != "$expected" ]; then
    set +x
    echo "EXPECTED: $expected"
    echo "ACTUAL: $actual"
    failwith "assertion failed"
  else
    set -x
    echo "$actual"
  fi
}
export -f expectStdout

info () {
  set +x
  echo "INFO:" "$@"
  set -x
}
export -f info
