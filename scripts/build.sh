#!/bin/bash
set -e

OS_NAME="$(uname -s)"

if [[ "$OS_NAME" -eq "Linux" ]] || [["$OS_NAME" -eq "Darwin" ]]; then
    make ci
    make ESY_RELEASE_TAG="$TRAVIS_TAG" build platform-release
else
    npm run build
    jest test-e2e
    npm run test:unit
    npm run test:e2e-slow
    npm run release:make-platform-package
fi
