.DELETE_ON_ERROR:

ESY_EXT := $(shell command -v esy 2> /dev/null)
ESY_VERSION := $(shell esy version)
ESY_VERSION_MINOR :=$(word 2, $(subst ., ,$(ESY_VERSION)))

BIN = $(PWD)/node_modules/.bin
PROJECTS = esy esy-build-package esyi
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

   bump-major-version  Bump major package version (commits & tags)
   bump-minor-version  Bump minor package version (commits & tags)
   bump-patch-version  Bump patch package version (commits & tags)

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

bootstrap:
ifndef ESY_EXT
	$(error "esy command is not avaialble, run 'npm install -g esy'")
endif
ifeq ($(ESY_VERSION_MINOR),2)
	@esy install
else
	$(error "esy command should be at least of version 0.2.0, run 'npm install -g esy'")
endif
	@make build-dev
	@ln -s $$(esy which fastreplacestring) $(PWD)/bin/fastreplacestring

doctoc:
	@$(BIN)/doctoc --notitle ./README.md

clean:
	@esy dune clean

build:
	@esy b dune build -j 4 $(TARGETS)

esy::
	@esy b dune build -j 4 _build/default/esy/Esy.cmxa

esyi::
	@esy b dune build -j 4 _build/default/esyi/EsyInstall.cmxa

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

refmt::
	@find $(PROJECTS) -name '*.re' \
		| xargs -n1 esy refmt --in-place --print-width 80

#
# Test
#

JEST = $(BIN)/jest

test-unit::
	@esy b dune build @runtest

test-e2e::
	@$(BIN)/jest test-e2e

test-e2e-slow::
	@node ./test-e2e-slow/run-slow-tests

test::
	@echo "Running test suite: unit tests"
	@$(MAKE) test-unit
	@echo "Running test suite: e2e"
	@$(MAKE) test-e2e

ci::
	@$(MAKE) test
	@$(MAKE) test-e2e-slow

#
# Release
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

#
# npm publish workflow
#

publish: release
	@(cd $(RELEASE_ROOT) && npm publish --access public --tag $(NPM_RELEASE_TAG))

bump-major-version:
	@npm version major

bump-minor-version:
	@npm version minor

bump-patch-version:
	@npm version patch

## Site

site-bootstrap:
	@$(MAKE) -C site bootstrap

site-start:
	@$(MAKE) -C site start

site-build:
	@$(MAKE) -C site build

site-publish:
	@$(MAKE) -C site publish
