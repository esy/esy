#!/usr/bin/env sh

# Helper script to setup the OPAM repository & OCaml/Reason build tools
#
# Uses the forked OPAM repository for Windows here:
# https://github.com/fdopen/opam-repository-mingw
#
# Other aspects of the script are based on the ocaml-ci-scripts:
# https://github.com/ocaml/ocaml-ci-scripts/blob/master/appveyor-opam.sh

SWITCH=${OPAM_SWITCH:-'4.06.1+mingw64c'}
OPAM_URL='https://github.com/fdopen/opam-repository-mingw/releases/download/0.0.0.1/opam64.tar.xz'
OPAM_ARCH=opam64

if [ "$PROCESSOR_ARCHITECTURE" != "AMD64" ] && \
       [ "$PROCESSOR_ARCHITEW6432" != "AMD64" ]; then
    OPAM_URL='https://github.com/fdopen/opam-repository-mingw/releases/download/0.0.0.1/opam32.tar.xz'
    OPAM_ARCH=opam32
fi

export OPAM_LINT="false"
export CYGWIN='winsymlinks:native'
export OPAMYES=1

get() {
  wget --quiet https://raw.githubusercontent.com/${fork_user}/ocaml-ci-scripts/${fork_branch}/$@
}

set -eu

curl -fsSL -o "${OPAM_ARCH}.tar.xz" "${OPAM_URL}"
tar -xf "${OPAM_ARCH}.tar.xz"
"${OPAM_ARCH}/install.sh" --quiet

opam init -a default "https://github.com/fdopen/opam-repository-mingw.git" --comp "$SWITCH" --switch "$SWITCH"
opam update

echo $(ocaml-env cygwin)
echo $(opam config env)

opam install depext-cygwinports depext
