#! /bin/bash

set -e

# shellcheck disable=SC2001
#   2001 complains bash variable substitution could be considered instead of echo/sed pattern
#   3060 complains of missing echo/sed pattern support in POSIX shell
#   We chose to ignore 2001

print_usage () {
    echo ""
    echo "fetch-github.sh"
    echo "--help                          Show this help message"
    echo "--org=<github org>              Specifies github organisation"
    echo "--repo=<repository name>        Specifies repository name"
    echo "--manifest=<manifest file>      Specifies manifest meant for this package from the repository"
    echo "--commit=<commit hash>          Specifies the commit"
    echo ""
}

# process command line options
while test $# -ge 1
do
case "$1" in
    -h* | --help)
	print_usage;
        exit 0 ;;
    --org=*)
	ORG=$(echo "$1" | sed 's/.*=//')
	shift;
	;;
    --repo=*)
	REPO=$(echo "$1" | sed 's/.*=//')
	shift;
	;;
    --manifest=*)
	OPAM_FILE_NAME=$(echo "$1" | sed 's/.*=//')
	shift;
	;;
    --commit=*)
	COMMIT=$(echo "$1" | sed 's/.*=//')
	shift;
	;;
    --clone-dir=*)
	CLONE_DIR=$(echo "$1" | sed 's/.*=//')
	shift;
	;;
    *)
	shift;
	;;
    esac
done

rm -rf "$CLONE_DIR"
git clone "https://github.com/$ORG/$REPO" "$CLONE_DIR"
cd "$CLONE_DIR"
git checkout "$COMMIT"
