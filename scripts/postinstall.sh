#!/bin/bash

set -e
set -u
set -o pipefail

#
# Spit out config for Esy executables implemented in bash
#

(cd bin && node ./esy.js autoconf > ./esyConfig.sh)
