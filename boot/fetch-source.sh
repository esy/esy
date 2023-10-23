#! /bin/bash

# DEPRECATED
# It's better to use esy to download all the sources with `esy i --cache-tarballs-path`

set -ex

# shellcheck disable=SC2001
#   2001 complains bash variable substitution could be considered instead of echo/sed pattern
#   3060 complains of missing echo/sed pattern support in POSIX shell
#   We chose to ignore 2001

print_usage () {
    echo ""
    echo "fetch-source.sh"
    echo "--help                          Show this help message"
    echo "--output-file=<path/to/tarball> Specifies path where tarball can be downloaded"
    echo "--url=<url of the tarball>      Specifies url of the tarball to be downloaded"
    echo "--checksum=<checksum hash>      Specifies the checksum of the tarball"
    echo "--checksum-algorithm=<sha256 | sha512> Specifies the hashing algorithm of the checksum"
    echo ""
}

# process command line options
while test $# -ge 1
do
case "$1" in
    -h* | --help)
	print_usage;
        exit 0 ;;
    --output-file=*)
	OUTPUT_FILE=$(echo "$1" | sed 's/.*=//')
	shift;
	;;
    --url=*)
	URL=$(echo "$1" | sed 's/.*=//')
	shift;
	;;
    --checksum=*)
	CHECKSUM=$(echo "$1" | sed 's/.*=//')
	shift;
	;;
    --checksum-algorithm=*)
	CHECKSUM_ALGORITHM=$(echo "$1" | sed 's/.*=//')
	shift;
	;;
    # --reason)
    # 	REASON=1
    # 	shift;
    # 	;;
    *)
	shift;
	;;
    esac
done

verify_checksum() {
    CHECKSUM="$1"
    CHECKSUM_ALGORITHM="$2"
    OUTPUT_FILE="$3"
    CHECKSUM_CMD=""
    case "$CHECKSUM_ALGORITHM" in
	"md5")
	    CHECKSUM_CMD="printf '%s  %s' $CHECKSUM $OUTPUT_FILE | md5sum --check"
	    ;;
	sha*)
	    SHASUM_ALGO="$(echo "$CHECKSUM_ALGORITHM" | sed s/sha//)"
	    CHECKSUM_CMD="printf '%s  %s' $CHECKSUM $OUTPUT_FILE | shasum -a $SHASUM_ALGO -c"
	    ;;
    esac
    bash -c "$CHECKSUM_CMD"
}


curl -s -o "$OUTPUT_FILE" "$URL"
verify_checksum "$CHECKSUM" "$CHECKSUM_ALGORITHM" "$OUTPUT_FILE"
mkdir -p sources
tar -xf "$OUTPUT_FILE" -C sources/
