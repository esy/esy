#!/bin/bash
#
# This is config and runtime lib for esy commands implemented in bash.
# It should be sourced by the command before it starts doing anything meaninful
#
# Example minimal esy command:
#
#     #!/usr/bin/env bash
#
#     set -e
#     set -u
#     set -o pipefail
#
#     BINDIR=$(dirname "$0")
#     source "$BINDIR/esyConfig.sh"
#
#     echo "Hello, I work on "$ESY__SANDBOX"
#

BINDIR=$(dirname "$0")

if [ -z "${ESY__SANDBOX+x}" ]; then
  export ESY__SANDBOX="$PWD"
fi
if [ -z "${ESY__PREFIX+x}" ]; then
  export ESY__PREFIX="$HOME/.esy"
fi
if [ -z "${ESY__LOCAL_STORE+x}" ]; then
  export ESY__LOCAL_STORE="$ESY__SANDBOX/node_modules/.cache/_esy/store"
fi

#
# Get length of the string in C locale
#

esyStrLen() {
  # run in a subprocess to override $LANG variable
  LANG=C /bin/bash -c 'echo "${#0}"' "$1"
}

#
# Get length of the string in C locale
#

esyRepeatCharacter() {
  local charToRepeat=$1
  local times=$2
  printf "%0.s$charToRepeat" $(seq 1 "$times")
}

#
# Rewrite Esy store prefix at path.
#
# Example:
#
#   esyRewriteStorePrefix /path/to/build "origPrefix" "destPrefix"
#

esyRewriteStorePrefix () {
  local path="$1"
  local origPrefix="$2"
  local destPrefix="$3"
  find "$path" -type f -print0 \
    | xargs -0 -I {} -P 30 "$BINDIR/fastreplacestring.exe" "{}" "$origPrefix" "$destPrefix"
}

#
# Find source modification time
#
# Example:
#
#   esyFindSourceModTime /path/to/source
#

modTimeCommand="stat -c %Y"
case $(uname) in
  Darwin*)
    modTimeCommand="stat -f %m"
    ;;
  Linux*)
    ;;
  MSYS*);;
  *);;
esac

esyFindSourceModTime () {
  local root="$1"
  local maxMtime
  maxMtime=$(
    find "$root" \
    -type f -a \
    -not -name ".merlin" -a \
    -not -name "*.install" -a \
    -not -path "$root/node_modules/*" -a \
    -not -path "$root/node_modules" -a \
    -not -path "$root/_build/*" -a \
    -not -path "$root/_build" -a \
    -not -path "$root/_install/*" -a \
    -not -path "$root/_install" -a \
    -not -path "$root/_esy/*" -a \
    -not -path "$root/_esy" -a \
    -not -path "$root/_release/*" \
    -not -path "$root/_release" \
    -exec $modTimeCommand {} \; | sort -r | head -n1)
  echo "$maxMtime"
}

#
# Get global store path based on the prefix path.
#
# Example:
#
#   storePath=$(esyGetStorePathFromPrefix "$ESY__PREFIX")
#

esyGetStorePathFromPrefix() {
  local esyPrefix="$1"
  local storeVersion="3"
  local prefixLength
  local paddingLength

  # Remove trailing slash if any.
  esyPrefix="${esyPrefix%/}"

  prefixLength=$(esyStrLen "$esyPrefix/$storeVersion")
  paddingLength=$((ESY__STORE_PADDING_LENGTH - prefixLength))

  # Discover how much of the reserved relocation padding must be consumed.
  if [ "$paddingLength" -lt "0" ]; then
    echo "$esyPrefix is too deep inside filesystem, Esy won't be able to relocate binaries"
    exit 1;
  fi

  padding=$(esyRepeatCharacter '_' "$paddingLength")
  echo "$esyPrefix/$storeVersion$padding"
}

esyLogEnabled () {
  if [ ! -z "${DEBUG+x}" ] && [[ "$1" = $DEBUG ]]; then
    return 0
  else
    return 1
  fi
}

esyLog () {
  local level="$1"
  shift
  if esyLogEnabled "$level"; then
    >&2 echo "  $level" "$@"
  fi
}


if [ -n "$(type -t esyCommandHelp)" ] && [ "$(type -t esyCommandHelp)" = function ]; then
  if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    esyCommandHelp
    exit 0
  fi
fi
