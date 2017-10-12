set -e
set -u
set -o pipefail

# get the length of its argument
_esy-util-str-len() {
  # run in a subprocess to override $LANG variable
  LANG=C /bin/bash -c 'echo "${#0}"' "$1"
}

# `_esy-util-repeat-char a 10` repeaats a 10 number of times
_esy-util-repeat-char() {
  chToRepeat=$1
  times=$2
  printf "%0.s$chToRepeat" $(seq 1 $times)
}

