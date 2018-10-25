#!/bin/bash
set -e

case $(uname -s) in
Linux) OS=NIX;;
Darwin) OS=NIX;;
*) OS=WIN;
esac

if [[ "$OS_NAME" = "NIX" ]]; then
    make ci
    make ESY_RELEASE_TAG="$TRAVIS_TAG" build platform-release
else
    npm run build
    jest test-e2e
    npm run test:unit
    npm run test:e2e-slow
    npm run release:make-platform-package
fi
