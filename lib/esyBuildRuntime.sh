set -e
set -u
set -o pipefail

FG_RED='\033[0;31m'
FG_GREEN='\033[0;32m'
FG_WHITE='\033[1;37m'
FG_RESET='\033[0m'

ESY__BUILD_COMMAND="
let esy = require(\"$cur__root/package.json\").esy || {};
let build = esy.build || 'true';
build = Array.isArray(build) ? build.join(' && ') : build;
build;"

esy-prepare-install-tree () {
  mkdir -p $cur__target_dir
  mkdir -p          \
    $cur__install   \
    $cur__lib       \
    $cur__bin       \
    $cur__sbin      \
    $cur__man       \
    $cur__doc       \
    $cur__share     \
    $cur__etc
}

esy-shell () {
  /bin/bash \
    --noprofile \
    --rcfile <(echo "
      export PS1=\"[$cur__name sandbox] $ \";
      source $ESY__RUNTIME;
      set +e
      set +u
      set +o pipefail
    ")
}

esy-build-command () {
  echo -e "${FG_WHITE}*** $cur__name: building from source...${FG_RESET}"
  BUILD_LOG="$cur__target_dir/_esy_build.log"
  BUILD_CMD=`node -p "$ESY__BUILD_COMMAND"`
  set +e
  /bin/bash             \
    --noprofile --norc  \
    -e -u -o pipefail   \
    -c "$BUILD_CMD"     \
    > "$BUILD_LOG" 2>&1
  BUILD_RETURN_CODE="$?"
  set -e
  if [ "$BUILD_RETURN_CODE" != "0" ]; then
    if [ "$esy_build__source_type" == "local" ]; then
      echo -e "${FG_RED}*** $cur__name: build failied:\n"
      cat "$BUILD_LOG" | sed  's/^/  /'
      echo -e "${FG_RESET}"
    else
      echo -e "${FG_RED}*** $cur__name: build failied, see:\n\n  $BUILD_LOG\n\nfor details${FG_RESET}"
    fi
    esy-clean
    exit 1
  else
    echo -e "${FG_GREEN}*** $cur__name: build complete${FG_RESET}"
  fi
}

esy-clean () {
  rm -rf $cur__install
}

esy-build () {
  # TODO: that's a fragile check, we need to build in another location and then
  # mv to the $cur__install. Why we don't do this now is because we don't
  # assume everything we build is relocatable.
  if [ ! -d "$cur__install" ]; then
    esy-prepare-install-tree
    # TODO: we need proper locking mechanism here
    esy-build-command
  fi
}

esy-force-build () {
  esy-prepare-install-tree
  # TODO: we need proper locking mechanism here
  esy-build-command
}
