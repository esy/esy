#!/bin/bash
#
# Apart from esy environment, the following variables should be defined for this
# script to work.
#
# Eject-specific sandbox-wide variables:
#
#   $ESY_EJECT__ROOT — the root of eject
#   $ESY_EJECT__STORE — the store path
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

esyBuildLog="$cur__target_dir/_esy/log"
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

esyMessageBegin="$cur__name@$cur__version: building..."
esyMessageComplete="$cur__name@$cur__version: done"
esyMessageSeeLog="${FG_RED}$cur__name@$cur__version: build failed, see:\n\n $esyBuildLog\n\nfor details${FG_RESET}"
esyMessageSeeLogInlineHeader="${FG_RED}$cur__name@$cur__version: build failed:\n${FG_RESET}"

#
# Execute command in build sandbox.
#

esyExecCommand () {
  if [ "${1:-}" == "--silent" ]; then
    shift
    echo "# COMMAND: " "$@" >> "$esyBuildLog"
    esyExecCommandInSandbox "$@" >> "$esyBuildLog" 2>&1
  else
    esyExecCommandInSandbox "$@"
  fi
}

esyExecCommandInSandbox () {
  $esySandboxCommand /bin/bash   \
    --noprofile --norc           \
    -e -u -o pipefail            \
    -c "$*"
}

#
# Prepare build environment
#

esyPrepare () {

  esyLog "esy:shell-builder" "esyPrepare"

  # this invalidates installation
  rm -rf "$cur__install"
  rm -rf "$esy_build__install_root"

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
    esyRelocateSource
  elif [ "$esy_build__build_type" == "_build" ]; then
   if [ "$esy_build__source_type" == "immutable" ]; then
    esyRelocateSource
   elif [ "$esy_build__source_type" == "transient" ]; then
     esyRelocateBuildDir
   elif [ "$esy_build__source_type" == "root" ]; then
    true
   fi
  elif [ "$esy_build__build_type" == "out-of-source" ]; then
    true
  fi

  mkdir -p "$cur__target_dir/_esy"
  rm -f "$esyBuildLog"

  cd "$cur__root"
}

esyComplete () {
  esyLog "esy:shell-builder" "esyComplete"
  if [ "$esy_build__build_type" == "in-source" ]; then
    true
  elif [ "$esy_build__build_type" == "_build" ]; then
   if [ "$esy_build__source_type" == "immutable" ]; then
    true
   elif [ "$esy_build__source_type" == "transient" ]; then
     esyRelocateBuildDirComplete
   elif [ "$esy_build__source_type" == "root" ]; then
    true
   fi
  elif [ "$esy_build__build_type" == "out-of-source" ]; then
    true
  fi
}

#
# Prepare build environment (copy sources to $cur__root)
#

esyRelocateSource () {
  esyLog "esy:shell-builder" "esyRelocateSource"
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

esyRelocateBuildDir () {
  esyLog "esy:shell-builder" "esyRelocateBuildDir"

  # save original _build
  if [ -d "$esy_build__source_root/_build" ]; then
    mv "$esy_build__source_root/_build" "$cur__target_dir/_build.prev"
  fi

  mkdir -p "$cur__target_dir/_build"
  mv "$cur__target_dir/_build" "$esy_build__source_root/_build"
}

esyRelocateBuildDirComplete () {
  esyLog "esy:shell-builder" "esyRelocateBuildDirComplete"

  # save _build
  if [ -d "$esy_build__source_root/_build" ]; then
    mv "$esy_build__source_root/_build" "$cur__target_dir/_build"
  fi

  # restore original _build
  if [ -d "$cur__target_dir/_build.prev" ]; then
    mv "$cur__target_dir/_build.prev" "$esy_build__source_root/_build"
  fi
}

#
# Perform build
#

esyRunBuildCommands () {
  esyLog "esy:shell-builder" "esyRunBuildCommands"

  # Run esy.build
  for cmd in "${esy_build__build_command[@]}"
  do
    set +e
    esyExecCommand "$@" "$cmd"
    BUILD_RETURN_CODE="$?"
    set -e
    if [ "$BUILD_RETURN_CODE" != "0" ]; then
      if [ "${1:-}" == "--silent" ]; then
        esyReportFailure
      fi
      esyClean
      exit 1
    fi
  done

}

#
# Perform install
#

esyRunInstallCommands () {
  esyLog "esy:shell-builder" "esyRunInstallCommands"

  # Run esy.install
  for cmd in "${esy_build__install_command[@]}"
  do
    set +e
    esyExecCommand "$@" "$cmd"
    BUILD_RETURN_CODE="$?"
    set -e
    if [ "$BUILD_RETURN_CODE" != "0" ]; then
      if [ "${1:-}" == "--silent" ]; then
        esyReportFailure
      fi
      esyClean
      exit 1
    fi
  done

  # Relocate installation
  for filename in $(find $cur__install -type f); do
    "$ESY_EJECT__ROOT/bin/fastreplacestring.exe" "$filename" "$cur__install" "$esy_build__install_root"
  done

  mkdir -p "$cur__install/_esy"
  echo "$ESY_EJECT__STORE" > "$cur__install/_esy/storePrefix"

  mv "$cur__install" "$esy_build__install_root"

}

#
# Report build failure
#

esyReportFailure () {
  if [ "$esy_build__source_type" != "immutable" ] || [ ! -z "${CI+x}" ] ; then
    echo -e "$esyMessageSeeLogInlineHeader"
    echo -e "${FG_RED}"
    cat "$esyBuildLog" | sed  's/^/  /'
    echo -e "${FG_RESET}"
  else
    echo -e "$esyMessageSeeLog"
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
# Execute with arguments within the build environment
#

esyWithBuildEnv () {
  local returnCode
  esyPrepare
  set +e
  ("$@")
  returnCode="$?"
  set -e
  esyComplete
  if [ $returnCode -ne 0 ]; then
    exit $returnCode
  fi
}

#
# Build package
#

_esyBuild () {
  esyRunBuildCommands --silent
  esyRunInstallCommands --silent
}

esyBuild () {
  if [ "$esy_build__source_type" != "immutable" ]; then
    echo -e "$esyMessageBegin"
    esyClean
    esyWithBuildEnv _esyBuild
    echo -e "$esyMessageComplete"
  elif [ ! -d "$esy_build__install_root" ]; then
    echo -e "$esyMessageBegin"
    esyWithBuildEnv _esyBuild
    echo -e "$esyMessageComplete"
  fi
}

#
# Execute shell in build environment
#

_esyShell () {
  $esySandboxCommand /bin/bash   \
    --noprofile                     \
    --rcfile <(echo "
      export PS1=\"[$cur__name sandbox] $ \";
      source $ESY_EJECT__ROOT/bin/shell-builder.sh;
      set +e
      cd $cur__root
    ")
}

esyShell () {
  esyWithBuildEnv _esyShell
}

#
# Clean build artifacts
#

esyClean () {
  rm -rf "$esy_build__install_root"
}

esyLogEnabled () {
  if [ ! -z "${DEBUG+x}" ] && [[ "$1" = $DEBUG ]]; then
    return 0
  else
    return 1
  fi
}

esyLog () {
  local level="$1"
  shift
  if esyLogEnabled "$level"; then
    >&2 echo "  $level" "$@"
  fi
}
