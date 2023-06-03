
########################################################################################################
#                                                                                                      #
# TODO:												       #
# 												       #
#   This script is not usable in its current state. It assumes the NPM				       #
#   tarball contains binaries that dont need binary relocation[1]. This				       #
#   is not true any more.									       #
# 												       #
#   This script could however be reused once we start publishing built				       #
#   artifacts directly to Github as a part of releases.						       #
# 												       #
#   A script like this is useful to provide sh/pwsh scripts that a user				       #
#   can directly run to install esy.								       #
# 												       #
#   The docs could say,										       #
# 												       #
#   Run the following in your terminal, then follow the onscreen instructions.			       #
# 												       #
#   curl --proto '=https' -sSf https://esy.sh/install | sh					       #
#   												       #
#   Note that this would work only because esy doesn't have dynamic                                    #
#   library deps with specific version constraints, or hardcoded paths                                 #
# 												       #
#   References:											       #
#   1. Binary Relocation - https://esy.sh/docs/en/npm-release.html#relocating-artifacts-path-rewriting #
#   												       #
########################################################################################################

#!/bin/bash

set -e
set -o pipefail

ESY_SHA256="d24e64938f108d7161ed82bd7a9a9e9db869be6e54114f4431be3a53fb817887"
ESY_SOLVE_CUDF_SHA256="3cfb233e5536fe555ff1318bcff241481c8dcbe1edc30b5f97e2366134d3f234"

ESY_VERSION="0.6.0"
ESY_PREFIX=/usr/local/lib/esy
ESY_BIN=/usr/local/bin/esy

ESY_DOWNLOAD_DIR=/tmp/esy-release
ESY_SOLVE_CUDF_DOWNLOAD_DIR=/tmp/esy-solve-cudf-release

NOPROMPT=$1

error() {
  echo "ERROR:" "$@"
  exit 1
}

ask () {
  if [[ "$NOPROMPT" == "--noprompt" ]]; then
    REPLY='y'
  else
    read -p "$1 (Y/N) " -n 1 -r; echo
  fi
}

echo "Installing esy@${ESY_VERSION} into ${ESY_PREFIX}..."
if [ -d "$ESY_PREFIX" ]; then
    ask "Directory ${ESY_PREFIX} already exists. Do you want to remove it?"
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
      rm -rf "$ESY_PREFIX"
    else
      error "unable to install esy into ${ESY_PREFIX}"
    fi
fi

unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     PLATFORM=linux;;
    Darwin*)    PLATFORM=darwin;;
    CYGWIN*)    PLATFORM=win32;;
    MINGW*)     PLATFORM=win32;;
    *)          PLATFORM="UNKNOWN:${unameOut}"
esac

echo "Downloading distribution..."
wget --quiet -P "$ESY_DOWNLOAD_DIR" "https://registry.npmjs.org/esy/-/esy-${ESY_VERSION}.tgz"
wget --quiet -P "$ESY_SOLVE_CUDF_DOWNLOAD_DIR" https://registry.npmjs.org/esy-solve-cudf/-/esy-solve-cudf-0.1.10.tgz

echo "Checking integrity..."
if [[ $(shasum -a 256 $ESY_DOWNLOAD_DIR/esy-${ESY_VERSION}.tgz) != $ESY_SHA256* ]]; then
    error "esy package integrity check failed"
fi
if [[ $(shasum -a 256 $ESY_SOLVE_CUDF_DOWNLOAD_DIR/esy-solve-cudf-0.1.10.tgz) != $ESY_SOLVE_CUDF_SHA256* ]]; then
    error "esy-solve-cudf package integrity check failed"
fi

echo "Moving things in place..."
mkdir -p "$ESY_PREFIX/lib"
mkdir -p "$ESY_PREFIX/bin"

tar -xzf "$ESY_DOWNLOAD_DIR/esy-${ESY_VERSION}.tgz" -C /tmp/esy-release
tar -xzf "$ESY_SOLVE_CUDF_DOWNLOAD_DIR/esy-solve-cudf-0.1.10.tgz" -C /tmp/esy-solve-cudf-release

cp "$ESY_DOWNLOAD_DIR/package/package.json" "$ESY_PREFIX"
cp "$ESY_DOWNLOAD_DIR/package/platform-$PLATFORM/_build/default/bin/esyInstallRelease.js" "$ESY_PREFIX/bin"

cp -r "$ESY_DOWNLOAD_DIR/package/platform-$PLATFORM/_build/default" "$ESY_PREFIX/lib"

chmod 0555 "$ESY_PREFIX/lib/default/bin/esy.exe"
chmod 0555 "$ESY_PREFIX/lib/default/bin/esyBuildPackageCommand.exe"
chmod 0555 "$ESY_PREFIX/lib/default/esy-build-package/bin/esyRewritePrefixCommand.exe"

mkdir -p "$ESY_PREFIX/lib/node_modules/esy-solve-cudf"
cp "$ESY_SOLVE_CUDF_DOWNLOAD_DIR/package/package.json" "$ESY_PREFIX/lib/node_modules/esy-solve-cudf"
cp "$ESY_SOLVE_CUDF_DOWNLOAD_DIR/package/platform-$PLATFORM/esySolveCudfCommand.exe" "$ESY_PREFIX/lib/node_modules/esy-solve-cudf"

echo "Cleaning up temporary artifacts..."
rm -rf "$ESY_DOWNLOAD_DIR"
rm -rf "$ESY_SOLVE_CUDF_DOWNLOAD_DIR"

echo "Installation complete! esy@${ESY_VERSION} is at ${ESY_PREFIX}."

ask "Do you want to create an ${ESY_BIN} symlink?"
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    if [ -f "${ESY_BIN}" ]; then
      ask "File ${ESY_BIN} already exists. Remove it?"
      if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        rm "${ESY_BIN}"
        ln -s "$ESY_PREFIX/lib/default/bin/esy.exe" "$ESY_BIN"
      fi
    else
      ln -s "$ESY_PREFIX/lib/default/bin/esy.exe" "$ESY_BIN"
    fi
fi
