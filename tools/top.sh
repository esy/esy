#! /bin/sh

set -e

TMPDIR="$cur__target_dir/tmp";
mkdir -p $TMPDIR;
touch $HOME/.rtop-history
dune top | sed "s/\;\;/\;/g" > "$TMPDIR/$cur__name.re";
rtop -init "$TMPDIR/$cur__name.re" "$@"
