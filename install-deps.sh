#!/usr/bin/env bash

set -euo pipefail

# install gmake, make command line on FreeBSD is BSD's make
# we need GNU make
sudo pkg install gmake

# we need to setup ocaml version 4.08.1, the official package of
# FreeBSD have version 4.05.0, so let's build it from source
set -ex;
    #curl -L --show-error --retry 5 -o ocaml-4.08.1.tar.gz https://github.com/ocaml/ocaml/archive/4.08.1.tar.gz; \
    tar -xvzf ocaml-4.08.1.tar.gz; \
    cd ocaml-4.08.1; \
    # create directory for ocaml prefix
    mkdir -p ~/.config/esy-ocaml; \
    ./configure CC=cc -disable-cfi --prefix="${HOME}/.config/esy-ocaml"; \
    gmake -j4 world.opt; \
    gmake install

# set the PATH to our compiled directory, so we have our ocaml version
export PATH=~/.config/esy-ocaml/bin;$PATH

# initialize opam and create switch
set -ex; \
    ocaml --version; \
    opam init; \
    opam switch create esy-build ocaml-system.4.08.1

set -ex; \
    opam install "yojson=1.7.0"; \
    opam install "reason=3.5.2"; \
    opam install "re=1.9.0"; \
    opam install "ppx_sexp_conv=v0.13.0"; \
    opam install "ppx_let=v0.13.0"; \
    opam install "ppx_inline_test=v0.13.0"; \
    opam install "ppx_expect=v0.13.0"; \
    opam install "ppx_deriving_yojson=3.5.1"; \
    opam install "ppx_deriving=4.4"; \
    opam install "opam-state=2.0.5"; \
    opam install "opam-format=2.0.5"; \
    opam install "opam-file-format=2.0.0"; \
    opam install "opam-core=2.0.5"; \
    opam install "ocamlformat=0.14.0"; \
    opam install "menhir=20200211"; \
    opam install "lwt_ppx=1.2.4"; \
    opam install "lwt=4.4.0"; \
    opam install "logs=0.7.0"; \
    opam install "lambda-term=2.0.2"; \
    opam install "fpath=0.7.2"; \
    opam install "fmt=0.8.8"; \
    opam install "dune=2.2.0"; \
    opam install "dose3=5.0.1"; \
    opam install "cudf=0.9"; \
    opam install "bos=0.2.0"; \
    # pinned
    opam pin rely https://github.com/facebookexperimental/reason-native.git; \
    opam pin cmdliner https://github.com/esy-ocaml/cmdliner.git#e9316bc; \
    opam pin angstrom https://github.com/esy-ocaml/angstrom#5a06a0; \
    # then build
    dune build -p esy,esy-build-package 