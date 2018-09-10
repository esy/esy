#!/usr/bin/env sh

# install-opam-dependencies.sh
#
# This installs OPAM dependencies such that `esy` can be built without depending on `esy` itself.

set -u
set -e
set -o pipefail

# we resset symlink mode so that tar command doesn't fail by extracting symlinks
# before their corresponding targets (this happens for example files inside
# angstrom archive). Then we set the mode back to native symlinks.
export CYGWIN=''
opam install --yes angstrom
export CYGWIN='winsymlinks:native'

opam install --yes ocaml-migrate-parsetree
opam install --yes reason
opam install --yes cmdliner
opam install --yes lwt.3.3.0
opam install --yes lwt_ppx
opam install --yes menhir
opam install --yes ppx_inline_test
opam install --yes ppx_let
opam install --yes ppx_deriving_yojson
opam install --yes yojson
opam install --yes bos
opam install --yes re

opam install --yes opam-format
opam install --yes opam-state
opam install --yes cudf
opam install --yes dose3

echo "** Installed packages:"
ocamlfind list
