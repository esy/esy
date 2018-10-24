#!/bin/bash
set -ev

make ci
make ESY_RELEASE_TAG="$TRAVIS_TAG" build platform-release
