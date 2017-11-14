#!/bin/bash
#
# Apart from esy environment, the following variables should be defined for this
# script to work.
#
# Eject-specific sandbox-wide variables:
#
#   $ESY_EJECT__ROOT — the root of eject
#
# Eject-specific build-specific variables:
#
#   $esy_build__sandbox_config_darwin - the location of darwin (sandbox-exec)
#   $esy_build__source_root - the location of real source root
#   $esy_build__install_root - the location of final install
#   $esy_build__build_type - the build type
#   $esy_build__source_type - the build source type
#   $esy_build__build_command - an array of build commands
#   $esy_build__install_command - an arrau of install command
#

set -e
set -u
set -o pipefail

if [ -z "${TMPDIR+x}" ] || [ "$TMPDIR" == "" ]; then
  unset TMPDIR
fi

FG_RED='\033[0;31m'
FG_GREEN='\033[0;32m'
FG_WHITE='\033[1;37m'
FG_RESET='\033[0m'

# Configure sandbox mechanism
esySandboxCommand=""
esyMtimeCommand="stat -c %Y"
case $(uname) in
  Darwin*)
    esySandboxCommand="sandbox-exec -f $esy_build__sandbox_config_darwin"
    esyMtimeCommand="stat -f %m"
    ;;
  Linux*)
    ;;
  MSYS*);;
  *);;
esac

#
# Execute command in build sandbox.
#

esyExecCommand () {
  $esySandboxCommand /bin/bash   \
    --noprofile --norc              \
    -e -u -o pipefail               \
    -c "$*"
}

#
# Prepare build environment
#

esyPrepareBuild () {

  rm -rf "$cur__install"

  # prepare build and installation directory
  mkdir -p                  \
    "$cur__target_dir"      \
    "$cur__install"         \
    "$cur__lib"             \
    "$cur__bin"             \
    "$cur__sbin"            \
    "$cur__man"             \
    "$cur__doc"             \
    "$cur__share"           \
    "$cur__etc"

  if [ "$esy_build__build_type" == "in-source" ]; then
    esyCopySourceRoot
  elif [ "$esy_build__build_type" == "_build" ] && [ "$esy_build__source_type" != "root" ] ; then
    esyCopySourceRoot
  fi

  mkdir -p "$cur__target_dir/_esy"

}

#
# Prepare build environment (copy sources to $cur__root)
#

esyCopySourceRoot () {
  rm -rf "$cur__root";
  rsync --quiet --archive     \
    --exclude "$cur__root"    \
    --exclude "node_modules"  \
    --exclude "_build"        \
    --exclude "_release"      \
    --exclude "_esybuild"     \
    --exclude "_esyinstall"   \
    "$esy_build__source_root/" "$cur__root"
}

#
# Perform build
#

esyPerformBuild () {

  esyPrepareBuild

  cd "$cur__root"

  echo -e "${FG_GREEN}  → ${FG_RESET}$cur__name @ $cur__version"
  local buildLog="$cur__target_dir/_esy/log"
  rm -f "$buildLog"

  # Run esy.build
  for cmd in "${esy_build__build_command[@]}"
  do
    set +e
    echo "# COMMAND: $cmd" >> "$buildLog"
    esyExecCommand "$cmd" >> "$buildLog" 2>&1
    BUILD_RETURN_CODE="$?"
    set -e
    if [ "$BUILD_RETURN_CODE" != "0" ]; then
      esyReportFailure "$buildLog"
      esyClean
      exit 1
    fi
  done

}

#
# Perform install
#

esyPerformInstall () {

  local buildLog="$cur__target_dir/_esy/log"

  # Run esy.install
  for cmd in "${esy_build__install_command[@]}"
  do
    set +e
    echo "# COMMAND: $cmd" >> "$buildLog"
    esyExecCommand "$cmd" >> "$buildLog" 2>&1
    BUILD_RETURN_CODE="$?"
    set -e
    if [ "$BUILD_RETURN_CODE" != "0" ]; then
      esyReportFailure "$buildLog"
      esyClean
      exit 1
    fi
  done

  # Relocate installation
  for filename in $(find $cur__install -type f); do
    "$ESY_EJECT__ROOT/bin/fastreplacestring.exe" "$filename" "$cur__install" "$esy_build__install_root"
  done
  mv "$cur__install" "$esy_build__install_root"
  echo -e "${FG_GREEN}  → $cur__name @ $cur__version: complete${FG_RESET}"

}

#
# Report build failure
#

esyReportFailure () {
  local buildLog="$1"
  if [ "$esy_build__source_type" != "immutable" ] || [ ! -z "${CI+x}" ] ; then
    echo -e "${FG_RED}  → $cur__name @ $cur__version: build failed:\n"
    cat "$buildLog" | sed  's/^/  /'
    echo -e "${FG_RESET}"
  else
    echo -e "${FG_RED}  → $cur__name @ $cur__version: build failed, see:\n\n $buildLog\n\nfor details${FG_RESET}"
  fi
}

esyMaxBuildMtime () {
  local root="$1"
  local maxMtime
  maxMtime=$(
    find "$root" \
    -not -path "$root/node_modules/*" -a \
    -not -path "$root/node_modules" -a \
    -not -path "$root/_build" -a \
    -not -path "$root/_install" -a \
    -not -path "$root/_esy" -a \
    -not -path "$root/_release" -a \
    -exec $esyMtimeCommand {} \; | sort -r | head -n1)
  echo "$maxMtime"
}

#
# Build package
#

esyBuild () {
  if [ "$esy_build__source_type" != "immutable" ]; then
    esyClean
    esyPerformBuild
    esyPerformInstall
  elif [ ! -d "$esy_build__install_root" ]; then
    esyPerformBuild
    esyPerformInstall
  fi
}

#
# Execute shell in build environment
#

esyShell () {
  esyPrepareBuild
  $esySandboxCommand /bin/bash   \
    --noprofile                     \
    --rcfile <(echo "
      export PS1=\"[$cur__name sandbox] $ \";
      source $ESY_EJECT__ROOT/bin/runtime.sh;
      set +e
      set +u
      set +o pipefail
      cd $cur__root
    ")
}

#
# Clean build artifacts
#

esyClean () {
  rm -rf "$esy_build__install_root"
}
