set -e
set -u
set -o pipefail

FG_RED='\033[0;31m'
FG_GREEN='\033[0;32m'
FG_WHITE='\033[1;37m'
FG_RESET='\033[0m'

ESY__SANDBOX_COMMAND=""

if [[ "$esy__platform" == "darwin" ]]; then
  ESY__SANDBOX_COMMAND="sandbox-exec -f $cur__target_dir/_esy_sandbox.sb"
fi

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
  $ESY__SANDBOX_COMMAND /bin/bash   \
    --noprofile                     \
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
  set +e
  $ESY__SANDBOX_COMMAND /bin/bash   \
    --noprofile --norc              \
    -e -u -o pipefail               \
    -c "$esy_build__command"        \
    > "$BUILD_LOG" 2>&1
  BUILD_RETURN_CODE="$?"
  set -e
  if [ "$BUILD_RETURN_CODE" != "0" ]; then
    if [ "$esy_build__source_type" == "local" ] || [ ! -z "${CI+x}" ] ; then
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

esy-copy-permissions () {
  chmod `stat -f '%p' "$1"` "${@:2}"
}

esy-replace-string () {
  FILE="$1"
  SRC_STRING="$2"
  DEST_STRING="$3"
  # TODO: get rid of python here
  python -c "
with open('$FILE', 'r') as input_file:
  data = input_file.read()
data = data.replace('$SRC_STRING', '$DEST_STRING')
with open('$FILE', 'w') as output_file:
  output_file.write(data)
  "
}

esy-commit-install () {
  for filename in `find $cur__install -type f`; do
    esy-replace-string "$filename" "$cur__install" "$esy_build__install"
  done
  mv $cur__install $esy_build__install
}

esy-clean () {
  rm -rf $esy_build__install
}

esy-build () {
  if [ ! -d "$esy_build__install" ]; then
    esy-prepare-install-tree
    esy-build-command
    esy-commit-install
  fi
}

esy-force-build () {
  esy-prepare-install-tree
  esy-build-command
  esy-clean
  esy-commit-install
}
