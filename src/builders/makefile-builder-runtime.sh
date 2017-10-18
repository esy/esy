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
  Darwin*) ESY__SANDBOX_COMMAND="sandbox-exec -f $cur__target_dir/_esy/sandbox.sb";;
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
  if [ "$esy_build__type" == "in-source" ]; then
    rm -rf $cur__root;
    rsync --quiet --archive \
      --exclude "$cur__root" \
      $esy_build__source_root/ $cur__root
  fi

  mkdir -p $cur__target_dir/_esy
  $ESY_EJECT__ROOT/bin/render-env $esy_build__eject/sandbox.sb.in $cur__target_dir/_esy/sandbox.sb

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
