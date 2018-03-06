#!/bin/bash

set -e
set -u
set -o pipefail

case $(uname) in
  Darwin*)
    cp bin/esy-darwin bin/esy
    cp bin/esyBuildPackage-darwin bin/esyBuildPackage
    ;;
  Linux*)
    cp bin/esy-linux bin/esy
    cp bin/esyBuildPackage-linux bin/esyBuildPackage
    ;;
  *)
    echo "Unsupported operating system $(uname), exiting...";
    exit 1
    ;;
esac

chmod +x ./bin/esy
chmod +x ./bin/esyBuildPackage
