#!/bin/bash
set -ev

OS_NAME=$(uname -s)

if [[ "$OS_NAME" == "Linux"]] || [[ "$OS_NAME" == "Darwin" ]]; then
make bootstrap
else
npm install -g jest-cli
cp scripts/build/patched-bash-exec.js C:/Users/appveyor/AppData/Roaming/npm/node_modules/esy/node_modules/esy-bash/bash-exec.js
travis_retry esy install
fi
