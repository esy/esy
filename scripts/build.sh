#!/bin/bash
set -ev

case $(uname -s) in
Linux) OS=NIX;;
Darwin) OS=NIX;;
*) OS=WIN;
esac

if [[ "$OS" = "NIX" ]]; then

    # Linux / OSX build
    make ci
    make ESY_RELEASE_TAG="$TRAVIS_TAG" build platform-release

else

    # Windows build
    powershell.exe npm run build
    powershell.exe jest test-e2e
    powershell.exe npm run test:unit
    powershell.exe npm run test:e2e-slow
    powershell.exe npm run release:make-platform-package

fi
