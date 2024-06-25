#! /bin/sh

set -e

TMPDIR="$cur__root/_esy/default/tmp";
mkdir -p "$TMPDIR";
touch "$TMPDIR/.rtop-history"
DIR_NAME="$(basename $PWD)"
WITH_LOAD_FILES="$TMPDIR/$cur__name__$DIR_NAME.re"
dune top | sed "s/\;\;/\;/g" > "$WITH_LOAD_FILES";
rtop -init "$WITH_LOAD_FILES" "$@"
