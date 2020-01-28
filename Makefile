.DELETE_ON_ERROR:

ESY_EXT := $(shell command -v esy 2> /dev/null)
ESY_VERSION := $(shell esy version)
ESY_VERSION_MINOR :=$(word 2, $(subst ., ,$(ESY_VERSION)))

BIN = $(PWD)/node_modules/.bin
PROJECTS = esy esy-build-package
VERSION = $(shell node -p "require('./package.json').version")
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
 that you can use "bin/esy" executable to run the development version of esy
 command. Enjoy!

 Common tasks:

   bootstrap           Bootstrap the development environment
   test                Run tests
   clean               Clean build artefacts

 Release tasks:

   publish             Build release and run 'npm publish'

   release             Produce an npm release inside _release, use ESY_RELEASE_TAG
                       to control for which tag to fetch platform releases from GitHub

   platform-release    Produce a plartform specific release inside _platformrelease.

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
	$(error "esy command is not avaialble, run 'npm install -g esy@0.$(ESY_VERSION_MINOR).x'")
endif
ifeq ($(ESY_VERSION_MINOR),5)
	@esy install
	@make build
	@node scripts/bootstrap.js
else
	$(error "esy requires version 0.$(ESY_VERSION_MINOR).x installed to bootstrap, run 'npm install -g esy@0.$(ESY_VERSION_MINOR).x'")
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

#
# Test
#

test-unit::
	esy test:unit

test-e2e::
	./node_modules/.bin/jest test-e2e

test-e2e-slow::
	esy test:e2e-slow

test::
	@echo "Running test suite: unit tests"
	@$(MAKE) test-unit
	@echo "Running test suite: e2e"
	@$(MAKE) test-e2e

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
