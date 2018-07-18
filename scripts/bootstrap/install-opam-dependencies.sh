#!/usr/bin/env sh

# install-opam-dependencies.sh
#
# This installs OPAM dependencies such that `esy` can be built without depending on `esy` itself.

set -u
set -e
set -o pipefail

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
opam install --yes cudf
opam install --yes dose3

echo "** Installed packages:"
ocamlfind list
