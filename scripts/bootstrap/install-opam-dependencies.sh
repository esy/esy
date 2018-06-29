#!/usr/bin/env sh

# install-opam-dependencies.sh
#
# This installs OPAM dependencies such that `esy` can be built without depending on `esy` itself.

opam install --yes ocaml-migrate-parsetree
opam install --yes reason
opam install --yes cmdliner
opam install --yes lwt
opam install --yes menhir
opam install --yes ppx_let
opam install --yes ppx_deriving_yojson
opam install --yes lwt_ppx
opam install --yes yojson
opam install --yes bos
opam install --yes re
