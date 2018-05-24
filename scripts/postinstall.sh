#!/bin/bash

set -e
set -u
set -o pipefail

case $(uname) in
  Darwin*)
    (cd _build/default && \
      mv esy/bin/esyCommand-darwin.exe esy/bin/esyCommand.exe && \
      mv esyi/bin/esyi-darwin.exe esyi/bin/esyi.exe && \
      mv esy-build-package/bin/esyBuildPackageCommand-darwin.exe esy-build-package/bin/esyBuildPackageCommand.exe)
    ;;
  Linux*)
    (cd _build/default && \
      mv esy/bin/esyCommand-linux.exe esy/bin/esyCommand.exe && \
      mv esyi/bin/esyi-linux.exe esyi/bin/esyi.exe && \
      mv esy-build-package/bin/esyBuildPackageCommand-linux.exe esy-build-package/bin/esyBuildPackageCommand.exe)
    ;;
  *)
    echo "Unsupported operating system $(uname), exiting...";
    exit 1
    ;;
esac
