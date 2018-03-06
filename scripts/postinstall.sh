#!/bin/bash

set -e
set -u
set -o pipefail

case $(uname) in
  Darwin*)
    cp -rf _build-darwin _build
    ;;
  Linux*)
    cp -rf _build-linux _build
    ;;
  *)
    echo "Unsupported operating system $(uname), exiting...";
    exit 1
    ;;
esac
