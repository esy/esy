#! /bin/sh


TARBALLS="$PWD/_boot/tarballs"
SOURCE_CACHE_PATH="$PWD/_boot/sources"
for TARBALL_PATH in $(find "$TARBALLS")
do
    echo "Extracting $TARBALL_PATH"
    FILENAME="$(basename $TARBALL_PATH)"
    DIR="${FILENAME%.tgz}"
    echo "File: $FILENAME"
    echo "Dir: $DIR"
    SOURCE_CACHE_ENTRY="$SOURCE_CACHE_PATH/$DIR"
    mkdir -p "$SOURCE_CACHE_ENTRY"
    tar -xf "$TARBALL_PATH" -C "$SOURCE_CACHE_ENTRY"
done
