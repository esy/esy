#! /bin/sh

set -e

get_major() {
    version="$1"
    echo "$version" | cut -d. -f1
}

get_minor() {
    version="$1"
    echo "$version" | cut -d. -f2
}

get_patch() {
    version="$1"
    echo "$version" | cut -d. -f3 | cut -d- -f1
}

next_version() {
    version="$1"
    major=$(get_major "$version")
    minor=$(get_minor "$version")
    next_minor=$((minor + 1))
    
    echo "$major.$next_minor.0"
}

get_version_ocaml() {
    version="$1"
    echo "let version = \"$version\""
}

get_version_reason() {
    version="$1"
    echo "let version = \"$version\";"
}

semver_version() {
    version="$1"
    tag="$2"

    if [ ! -z "$tag" ]
    then
	tag="nightly"
    fi

    echo "$version" | sed -e "s/-[0-9]-g/+$tag./"
}

print_usage () {
    echo ""
    echo "version.sh"
    echo "--help              Show this help message"
    echo "--plain             Show version as plain text"
    echo "--reason            Show a Reason let statement with version string"
    echo "--ocaml             Show a OCaml let statement with version string"
    echo ""
}

# process command line options
while test $# -ge 1
do
case "$1" in
    -h* | --help)
	print_usage;
        exit 0 ;;
    --plain)
	PLAIN=1
	shift;
	;;
    --reason)
	REASON=1
	shift;
	;;
    --next)
	NEXT=1
	shift;
	;;
    --ocaml)
	OCAML=1
	shift;
	;;
    --semver=*)
	SEMVER_TAG=`echo $1 | sed 's/.*=//'`;
	SEMVER=1;
	shift
	;;
    *)
	shift;
	;;
    esac
done

version=$(git describe --tags)

if [ ! -z "$NEXT" ]
then
    version=$(next_version "$version")
fi

if [ ! -z "$SEMVER" ]
then
    version=$(semver_version "$version" "$SEMVER_TAG")
fi

if [ ! -z "$OCAML" ]
then
    get_version_ocaml "$version"
elif [ ! -z "$REASON" ]
then
    get_version_reason "$version"
else
    echo "$version"
fi
