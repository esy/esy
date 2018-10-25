#!/bin/bash
set -ev

OSNAME=$(uname -s)

if [[ "$OS_NAME" == "Linux"]] || [[ "$OS_NAME" == "Darwin" ]]; then
    make ci
    make ESY_RELEASE_TAG="$TRAVIS_TAG" build platform-release
else
    npm run build
    jest test-e2e
    npm run test:unit
    npm run test:e2e-slow
    npm run release:make-platform-package
fi
