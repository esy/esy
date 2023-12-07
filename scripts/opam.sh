#! /bin/sh

init() {
    OPAM_COMPILER_BASE_PACKAGES="$1"
    PACKAGES="$2"
    opam init -y --disable-sandboxing --bare
    opam switch create esy-dev "$OPAM_COMPILER_BASE_PACKAGES$PACKAGES" -y --no-install
}

build() {
    opam exec -- dune build --only-packages=esy --profile release-static @install
}

install_artifacts() {
    PREFIX="$1"
    opam exec -- dune install --prefix "$PREFIX"
}

OPAM_COMPILER_BASE_PACKAGES="--packages=ocaml-variants.4.12.0+options,ocaml-option-flambda"
# MUSL_STATIC_PACKAGES=",ocaml-option-musl,ocaml-option-static"

case "$1" in
    "init")
	init "$OPAM_COMPILER_BASE_PACKAGES" "$MUSL_STATIC_PACKAGES"
	;;
    "install")
	opam install . --locked --deps-only -y
	;;
    "lock")
	opam lock .
	;;
    "build")
	build
	;;
    "install-artifacts")
	install_artifacts /usr/local
	;;
esac
