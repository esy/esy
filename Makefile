APP_ESY ?= $(PWD)
APP_ESY_INSTALL ?= /usr/local
RELEASE_ARGS ?= --no-env
OPAM_COMPILER_BASE_PACKAGES ?= "--packages=ocaml-variants.4.12.0+options,ocaml-option-flambda"
MUSL_STATIC_PACKAGES = ",ocaml-option-musl,ocaml-option-static"
SUDO ?= sudo

# This was conditional earlier. Every platform, including FreeBSD, will try to build a static build
RELEASE_ARGS += --static

OPAM_REPOSITORY_COMMIT ?= a05716d411352518e008c7b2aadafac20be218c1 # commit from 2 Jun, 2023
OPAM_REPOSITORY_URL =  "https://github.com/ocaml/opam-repository.git\#$(OPAM_REPOSITORY_COMMIT)"

openbsd:
	ulimit -s 10000
	ulimit -n 4096
	ftp -o /tmp/shasum1 https://fastapi.metacpan.org/source/MSHELOR/Digest-SHA-6.02/shasum
	sed -e 's|#!perl|#!/usr/bin/env perl|g' /tmp/shasum1 > /tmp/shasum
	rm /tmp/shasum1
	doas mv /tmp/shasum /usr/local/bin/
	doas chmod +x /usr/local/bin/shasum
	doas mkdir -p /app/esy-install && \
		doas chown -R $(USER):$(USER) /app/esy-install
	SUDO=doas APP_ESY=/app/esy MUSL_STATIC_PACKAGES="" \
			 APP_ESY_INSTALL=/app/esy-install gmake opam-setup
	SUDO=doas APP_ESY=/app/esy MUSL_STATIC_PACKAGES="" \
			 APP_ESY_INSTALL=/app/esy-install gmake docker

opam-init:
	opam init -y --disable-sandboxing --bare

opam-switch: 
	opam switch create . $(OPAM_COMPILER_BASE_PACKAGES)$(MUSL_STATIC_PACKAGES) -y --no-install

opam-install: 
	opam install . --locked --deps-only -y

opam-setup:
	make opam-init
	make opam-switch
	make opam-install

# ideally, build-with-opam should depend on opam-setup, but opam-setup cannot be run twice. opam switch create fails when repeated
build-with-opam:
	opam exec -- dune build -p esy
	opam exec -- dune build @install
	opam exec -- dune install --prefix $(APP_ESY_INSTALL)

dune-cleanup:
	opam exec -- dune clean

opam-cleanup:
	opam switch -y remove . || true
	opam clean
	rm -rf _opam

alpine-docker-image:
	docker build . -f dockerfiles/alpine.Dockerfile --network=host -t esydev/esy:nightly-alpine-latest

extracted-alpine-artifacts:
	docker container run -itd --network=host --name esy-container esydev/esy:nightly-alpine-latest
	docker cp esy-container:$(APP_ESY_INSTALL) $@

static:
	make alpine-docker-image
	make extracted-alpine-artifacts
