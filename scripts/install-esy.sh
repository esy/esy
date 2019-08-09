#!/bin/bash

ESY_SHA256="f2cec5e6556172141bb399d1dcef7db4b9d881b0bed9c9749c0eebd95584b739"
ESY_SOLVE_CUDF_SHA256="3cfb233e5536fe555ff1318bcff241481c8dcbe1edc30b5f97e2366134d3f234"

PREFIX=~/esy

ESY_DOWNLOAD_DIR=/tmp/esy-release
ESY_SOLVE_CUDF_DOWNLOAD_DIR=/tmp/esy-solve-cudf-release

echo "Removing old install"
rm -rf ~/esy
rm /usr/local/bin/esy

set -e

unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     PLATFORM=linux;;
    Darwin*)    PLATFORM=darwin;;
    CYGWIN*)    PLATFORM=win32;;
    MINGW*)     PLATFORM=win32;;
    *)          PLATFORM="UNKNOWN:${unameOut}"
esac

echo "Downloading needed packages from npm."

wget --quiet -P $ESY_DOWNLOAD_DIR https://registry.npmjs.org/esy/-/esy-0.5.8.tgz
wget --quiet -P $ESY_SOLVE_CUDF_DOWNLOAD_DIR https://registry.npmjs.org/esy-solve-cudf/-/esy-solve-cudf-0.1.10.tgz

echo "Checking shasums"
if [[ $PLATFORM == "darwin" ]]; then
    if [[ $(shasum -a 256 $ESY_DOWNLOAD_DIR/esy-0.5.8.tgz) == $ESY_SHA256* ]]; then
        ESY_MATCHES=true
    fi
    if [[ $(shasum -a 256 $ESY_SOLVE_CUDF_DOWNLOAD_DIR/esy-solve-cudf-0.1.10.tgz) == $ESY_SOLVE_CUDF_SHA256* ]]; then
        ESY_SOLVE_CUDF_MATCHES=true
    fi
elif [[ $PLATFORM == "linux" ]]; then
    if [[ $(sha256sum $ESY_DOWNLOAD_DIR/esy-0.5.8.tgz) == $ESY_SHA256* ]]; then
        ESY_MATCHES=true
    fi
    if [[ $(sha256sum $ESY_SOLVE_CUDF_DOWNLOAD_DIR/esy-solve-cudf-0.1.10.tgz) == $ESY_SOLVE_CUDF_SHA256* ]]; then
        ESY_SOLVE_CUDF_MATCHES=true
    fi
fi


if [[ $ESY_MATCHES && $ESY_SOLVE_CUDF_MATCHES ]]; then
    echo "Moving things in place"
    mkdir -p $PREFIX/lib
    mkdir -p $PREFIX/bin

    tar -xzf $ESY_DOWNLOAD_DIR/esy-0.5.8.tgz -C /tmp/esy-release
    tar -xzf $ESY_SOLVE_CUDF_DOWNLOAD_DIR/esy-solve-cudf-0.1.10.tgz -C /tmp/esy-solve-cudf-release

    cp $ESY_DOWNLOAD_DIR/package/package.json $PREFIX
    cp $ESY_DOWNLOAD_DIR/package/platform-$PLATFORM/_build/default/bin/esyInstallRelease.js $PREFIX/bin

    cp -r $ESY_DOWNLOAD_DIR/package/platform-$PLATFORM/_build/default $PREFIX/lib

    ln -s $PREFIX/lib/default/bin/esy.exe /usr/local/bin/esy
    chmod 0555 $PREFIX/lib/default/bin/esy.exe

    mkdir -p $PREFIX/lib/node_modules/esy-solve-cudf
gi
    cp $ESY_SOLVE_CUDF_DOWNLOAD_DIR/package/package.json $PREFIX/lib/node_modules/esy-solve-cudf
    cp $ESY_SOLVE_CUDF_DOWNLOAD_DIR/package/platform-$PLATFORM/esySolveCudfCommand.exe $PREFIX/lib/node_modules/esy-solve-cudf
fi

echo "Removing downloaded files"
rm -rf $ESY_DOWNLOAD_DIR
rm -rf $ESY_SOLVE_CUDF_DOWNLOAD_DIR

echo "Installed esy version $(esy --version)"
