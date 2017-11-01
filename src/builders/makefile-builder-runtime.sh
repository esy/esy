#
# Apart from esy environment, the following variables should be defined for this
# script to work.
#
#   $ESY_EJECT__ROOT — the root of eject
#
#   $esy_build__eject - the location of build eject
#   $esy_build__type - the build type
#   $esy_build__source_type - the build source type
#   $esy_build__source_root - the location of real source root
#   $esy_build__command - the build command
#   $esy_build__install - the location of final install
#

set -e
set -u
set -o pipefail

if [ "$TMPDIR" == "" ]; then
  unset TMPDIR
fi

FG_RED='\033[0;31m'
FG_GREEN='\033[0;32m'
FG_WHITE='\033[1;37m'
FG_RESET='\033[0m'

# Configure sandbox mechanism
ESY__SANDBOX_COMMAND=""
case $(uname) in
  Darwin*) ESY__SANDBOX_COMMAND="sandbox-exec -f $esy_build__eject/sandbox.sb";;
  Linux*);;
  MSYS*);;
  *);;
esac

_esy-prepare-build-env () {

  rm -rf $cur__install

  # prepare build and installation directory
  mkdir -p                \
    $cur__target_dir      \
    $cur__install         \
    $cur__lib             \
    $cur__bin             \
    $cur__sbin            \
    $cur__man             \
    $cur__doc             \
    $cur__share           \
    $cur__etc

  # for in-source builds copy sources over to build location
  if [ "$esy_build__type" == "in-source" ] || [ "$esy_build__type" == "_build" ]; then
    rm -rf $cur__root;
    rsync --quiet --archive     \
      --exclude "$cur__root"    \
      --exclude "node_modules"  \
      --exclude "_build"        \
      --exclude "_release"      \
      --exclude "_esybuild"     \
      --exclude "_esyinstall"   \
      $esy_build__source_root/ $cur__root
  fi

  mkdir -p $cur__target_dir/_esy

}

_esy-perform-build () {

  _esy-prepare-build-env

  cd $cur__root

  echo -e "${FG_WHITE}*** $cur__name @ $cur__version: building from source...${FG_RESET}"
  BUILD_LOG="$cur__target_dir/_esy/build.log"
  set +e
  $ESY__SANDBOX_COMMAND /bin/bash   \
    --noprofile --norc              \
    -e -u -o pipefail               \
    -c "$esy_build__command"        \
    > "$BUILD_LOG" 2>&1
  BUILD_RETURN_CODE="$?"
  set -e
  if [ "$BUILD_RETURN_CODE" != "0" ]; then
    if [ ! -z "${CI+x}" ] ; then
      echo -e "${FG_RED}*** $cur__name @ $cur__version: build failed:\n"
      cat "$BUILD_LOG" | sed  's/^/  /'
      echo -e "${FG_RESET}"
    else
      echo -e "${FG_RED}*** $cur__name @ $cur__version: build failed, see:\n\n  $BUILD_LOG\n\nfor details${FG_RESET}"
    fi
    esy-clean
    exit 1
  else
    for filename in `find $cur__install -type f`; do
      $ESY_EJECT__ROOT/bin/fastreplacestring.exe "$filename" "$cur__install" "$esy_build__install"
    done
    mv $cur__install $esy_build__install
    echo -e "${FG_GREEN}*** $cur__name @ $cur__version: build complete${FG_RESET}"
  fi

}

esy-build () {
  if [ "$esy_build__source_type" == "transient" ]; then
    esy-clean
    _esy-perform-build
  elif [ ! -d "$esy_build__install" ]; then
    _esy-perform-build
  fi
}

esy-shell () {
  _esy-prepare-build-env
  $ESY__SANDBOX_COMMAND /bin/bash   \
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

esy-clean () {
  rm -rf $esy_build__install
}
