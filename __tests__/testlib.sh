#!/bin/bash

set -e
set -o pipefail
set -u

info () {
  >&2 echo "$1"
}

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
  local command="$1"
  local expected="$2"
  local actual
  echo "RUNNING: $command"
  actual=$($command)
  if [ ! $? -eq 0 ]; then
    failwith "command failed"
  fi
  if [ "$actual" != "$expected" ]; then
    echo "EXPECTED: $expected"
    echo "ACTUAL: $actual"
    failwith "assertion failed"
  else
    echo "$actual"
  fi
}
export -f assertStdout

info () {
  echo "INFO:" "$@"
}
export -f info
