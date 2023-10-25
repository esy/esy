#! /bin/bash

set -x

ENV_FILE="$1"
PATH_FILE="$2"
DUNE_INSTALLATION="$3"
PREFIX="$4"
PACKAGE_NAME="$5"

if [ -f *.install ];
then
    if [ -f "$DUNE_INSTALLATION/bin/dune" ]
    then
	env -i -P "$(cat $PATH_FILE)" -S "$(cat $ENV_FILE)" "$DUNE_INSTALLATION/bin/dune" install --prefix="$PREFIX" -p "${PACKAGE_NAME#@opam/}";
    else
	rm -rf "$DUNE_INSTALLATION"
	cp -L -R _build/install/default "$DUNE_INSTALLATION"
	echo "Installed dune"
    fi
fi
