#!/bin/bash
set -e

OS_NAME="$(uname -s)"

if [[ "$OS_NAME" -eq "Linux" ]] || [["$OS_NAME" -eq "Darwin" ]]; then
make bootstrap
else

# Bring in travis_retry to get access to the function:
# https://gist.github.com/letmaik/caa0f6cc4375cbfcc1ff26bd4530c2a3
source travis_retry.sh

npm install -g jest-cli
cp scripts/build/patched-bash-exec.js C:/Users/appveyor/AppData/Roaming/npm/node_modules/esy/node_modules/esy-bash/bash-exec.js
travis_retry esy install
fi
