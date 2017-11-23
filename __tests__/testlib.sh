#!/bin/bash

set -e
set -o pipefail
set -u

# http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  SCRIPTDIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$SCRIPTDIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SCRIPTDIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

ESYCOMMAND="$SCRIPTDIR/../bin/esy"

initFixture () {
  local root
  local name
  local project

  name="$1"
  root=$(mktemp -d)
  project="$root/project"

  cp -r "fixtures/$name" "$project"

  esy () {
    "$ESYCOMMAND" "$@"
  }

  pushd "$project"
}

info () {
  >&2 echo "$1"
}

run () {
  echo "RUNNING: " "$@"
  "$@"
}

runAndExpectFailure () {
  echo "RUNNING (expecting failure): " "$@"
  set +e
  "$@"
  local ret="$?"
  set -e
  if [ $ret -eq 0 ]; then
    failwith "expected command to fail"
  fi
}

failwith () {
  >&2 echo "ERROR: $1"
  exit 1
}

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
