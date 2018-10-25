#!/bin/bash
set -e

case $(uname -s) in
Linux) OS=NIX;;
Darwin) OS=NIX;;
*) OS=WIN;
esac

echo $OS

travis_retry() {
    local result=0
    local count=1
    while [ $count -le 3 ]; do
        [ $result -ne 0 ] && {
        echo -e "\n${ANSI_RED}The command \"$@\" failed. Retrying, $count of 3.${ANSI_RESET}\n" >&2
    }
    # ! { } ignores set -e, see https://stackoverflow.com/a/4073372
    ! { "$@"; result=$?; }
    [ $result -eq 0 ] && break
    count=$(($count + 1))
    sleep 1
    done

    [ $count -gt 3 ] && {
    echo -e "\n${ANSI_RED}The command \"$@\" failed 3 times.${ANSI_RESET}\n" >&2
  }

  return $result
}

if [[ "$OS" = "NIX" ]]; then
make bootstrap
else
npm install -g jest-cli
cp scripts/build/patched-bash-exec.js C:/Users/appveyor/AppData/Roaming/npm/node_modules/esy/node_modules/esy-bash/bash-exec.js
travis_retry esy install
fi
