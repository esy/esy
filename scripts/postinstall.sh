#!/bin/bash

set -e
set -u
set -o pipefail

#
# Spit out config for Esy executables implemented in bash
#

set +e
(cd bin && node ./esy.js autoconf > ./esyConfig.sh)
ret=$?
set -e

if [ $ret -ne 0 ]; then
  echo "error:"
  cat bin/esyConfig.sh
  exit 1
fi

