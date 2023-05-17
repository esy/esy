.DELETE_ON_ERROR:

ESY_EXT := $(shell command -v esy 2> /dev/null)
ESY_VERSION := $(shell esy version)
ESY_VERSION_MINOR := $(word 2, $(subst ., ,$(ESY_VERSION)))
ESY_REQUIRED_VERSION_MINOR = 6

BIN = $(PWD)/node_modules/.bin
PROJECTS = esy esy-build-package
VERSION = $(shell esy node -p "require('./package.json').version")
PLATFORM = $(shell uname | tr '[A-Z]' '[a-z]')
NPM_RELEASE_TAG ?= latest
ESY_RELEASE_TAG ?= v$(VERSION)
GIT_BRANCH_NAME = $(shell git rev-parse --abbrev-ref HEAD)
GIT_COMMIT_SHA = $(shell git rev-parse --verify HEAD)

#
# Tools
#

.DEFAULT: help

define HELP

 Run "make bootstrap" if this is your first time with esy development. After
 that you can use "PATH_TO_REPO/bin/esy" executable to run the development version of esy
 command. Enjoy!

 Common tasks:

   bootstrap           Bootstrap the development environment
   test                Run tests
   clean               Clean build artefacts

 Release tasks:

    # TODO Describe release tasks

 Site tasks (https://esy.sh):

   site-bootstrap      Bootstrap dev environment for working on site.
   site-start          Serve site locally
   site-publish        Publish site to https://esy.sh (powered by GitHub Pages)
                       Note that the current USER environment variable will be used as a
                       GitHub user used for push. You can override it by setting GIT_USER
                       env: make GIT_USER=anna publish

 Other tasks:

   refmt               Reformal all *.re source with refmt

endef
export HELP

help:
	@echo "$$HELP"

bootstrap: install-githooks
ifndef ESY_EXT
	$(error "esy command is not avaialble, run 'npm install -g esy@0.$(ESY_REQUIRED_VERSION_MINOR).x'")
endif
ifeq ($(ESY_VERSION_MINOR),$(ESY_REQUIRED_VERSION_MINOR))
	@esy install
	@yarn install
	@make build
else
	$(error "esy requires version 0.$(ESY_REQUIRED_VERSION_MINOR).x installed to bootstrap, run 'npm install -g esy@0.$(ESY_REQUIRED_VERSION_MINOR).x'")
endif

GITHOOKS = $(shell git rev-parse --git-dir)/hooks
GITHOOKS_TO_INSTALL = $(shell ls -1 githooks)

install-githooks: $(GITHOOKS_TO_INSTALL:%=$(GITHOOKS)/%)

$(GITHOOKS)/%: githooks/%
	@cp $(<) $(@)
	@chmod +x $(@)

doctoc:
	@$(BIN)/doctoc --notitle ./README.md

clean:
	@esy dune clean

build:
	@esy b dune build -j 4 $(TARGETS)

esy::
	@esy b dune build -j 4 _build/default/esy/Esy.cmxa

esy-build-package::
	@esy b dune build -j 4 _build/default/esy-build-package/EsyBuildPackage.cmxa

esy-installer::
	@esy b dune build -j 4 _build/default/esy-installer/EsyInstaller.cmxa

esy-lib::
	@esy b dune build -j 4 _build/default/esy-lib/EsyLib.cmxa

doc:
	@esy b dune build @doc

b: build-dev
build-dev:
	@esy b dune build -j 4 $(TARGETS)

fmt refmt::
	@esy dune build @fmt --auto-promote

fmt-no-promote refmt-no-promote::
	@esy dune build @fmt


new-openbsd:
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
	SUDO=doas gmake static-link-patch
	SUDO=doas APP_ESY=/app/esy MUSL_STATIC_PACKAGES="" \
			 APP_ESY_INSTALL=/app/esy-install gmake new-docker

APP_ESY ?= $(PWD)
APP_ESY_INSTALL ?= /usr/local
APP_ESY_RELEASE ?= /app/_release
RELEASE_ARGS ?= --no-env
OPAM_COMPILER_BASE_PACKAGES ?= "--packages=ocaml-variants.4.12.0+options,ocaml-option-flambda"
MUSL_STATIC_PACKAGES = ",ocaml-option-musl,ocaml-option-static"
SUDO ?= sudo

static-link-patch:
	git -C $(APP_ESY)/esy-solve-cudf apply static-linking.patch && \
	git -C $(APP_ESY) apply static-linking.patch

# This was conditional earlier. Every platform, including FreeBSD, will try to build a static build
RELEASE_ARGS += --static

opam-setup:
	opam init -y --disable-sandboxing --bare https://github.com/ocaml/opam-repository.git#6ae77c27c7f831d7190928f9cd9002f95d3b6180
	opam switch create esy-local-switch $(OPAM_COMPILER_BASE_PACKAGES)$(MUSL_STATIC_PACKAGES)
	opam repository add duniverse "https://github.com/dune-universe/opam-overlays.git#c8f6ef0fc5272f254df4a971a47de7848cc1c8a4" # commit from 2 Jun, 2022.

opam-install-deps:
	opam install . --deps-only -y

# ideally, build-with-opam should depend on opam-setup, but opam-setup cannot be run twice. opam switch create fails when repeated
build-with-opam:
	opam exec -- dune build -p esy
	opam exec -- dune build @install
	opam exec -- dune install --prefix $(APP_ESY_INSTALL)

build-with-esy:
	$(APP_ESY_INSTALL)/bin/esy @static i --ocaml-pkg-name ocaml --ocaml-version 4.12.0 && \
	$(APP_ESY_INSTALL)/bin/esy @static b --ocaml-pkg-name ocaml --ocaml-version 4.12.0 && \
	$(APP_ESY_INSTALL)/bin/esy @static release $(RELEASE_ARGS) --ocaml-pkg-name ocaml --ocaml-version 4.12.0

opam-cleanup:
	opam exec -- dune uninstall --prefix $(APP_ESY_INSTALL)
	opam switch -y remove esy-local-switch
	opam clean

install-esy-artifacts:
	CXX=c++ yarn global --prefix=$(APP_ESY_INSTALL) --force add ${PWD}/_release
	mv _release $(APP_ESY_RELEASE)

new-docker:
	make opam-install-deps
	make build-with-opam
	make build-with-esy
	make opam-cleanup
	make install-esy-artifacts
#
# Test
#

test-unit::
	esy test:unit

test-e2e:: ./bin/esy
	@./node_modules/.bin/jest test-e2e

verdaccio::
	cd test-e2e-re/lib/verdaccio && npm install

test-e2e-re:: ./bin/esy verdaccio
	esy test:e2e-re

test-e2e-slow:: ./bin/esy
	@./node_modules/.bin/jest test-e2e-slow

test::
	@echo "Running test suite: unit tests"
	@$(MAKE) test-unit
	@echo "Running test suite: e2e"
	@$(MAKE) test-e2e
	@echo "Running test suite: e2e-re"
	@$(MAKE) test-e2e-re

ci::
	@$(MAKE) test
	@$(MAKE) test-e2e-slow

bin/esyInstallRelease.js: \
		esy-install-npm-release/esyInstallNpmRelease.build.js \
		esy-install-npm-release/esyInstallNpmRelease.js \
		esy-install-npm-release/Makefile
	@make -C esy-install-npm-release install build
	@cp $(<) $(@)

#
# Release workflow.
#
# - "release-tag" adds tag to the repository, which will make CI run full suite
#   of e2e tests (including slowtests).
#
# - "release-prepare" downloads a nightly release corresponding to the current
#   commit and "promotes" it to an esy release (fixes package name and version).
#
# - "release-publish" publishes what's inside "_release/package" directory to
#   npm.
#

release-tag:
ifneq ($(GIT_BRANCH_NAME),master)
	$(error "cannot tag on '$(GIT_BRANCH_NAME)' branch, 'master' branch required")
endif
	@git tag $(ESY_RELEASE_TAG)

release-prepare:
	@node ./scripts/promote-nightly-release.js $(GIT_COMMIT_SHA)

release-publish: release
	@(cd _release/package && npm publish --access public --tag $(NPM_RELEASE_TAG))

## Site

site-bootstrap:
	@$(MAKE) -C site bootstrap

site-start:
	@$(MAKE) -C site start

site-build:
	@$(MAKE) -C site build

site-publish:
	@$(MAKE) -C site publish
