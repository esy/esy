.DELETE_ON_ERROR:

ESY_EXT := $(shell command -v esy 2> /dev/null)

RELEASE_TAG ?= latest
BIN = $(PWD)/node_modules/.bin

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
   build-release       Produce an npm package ready to be published (useful for debug)

   bump-major-version  Bump major package version (commits & tags)
   bump-minor-version  Bump minor package version (commits & tags)
   bump-patch-version  Bump patch package version (commits & tags)

endef
export HELP

help:
	@echo "$$HELP"

bootstrap:
	@git submodule init
	@git submodule update
ifndef ESY_EXT
	$(error "esy command is not avaialble, run 'npm install -g esy'")
endif
	@make -C esy-install bootstrap
	@esy install
	@make build-dev
	@make -C test-e2e bootstrap

doctoc:
	@$(BIN)/doctoc --notitle ./README.md

clean:
	@rm -rf lib/
	@make -C esy-core clean

build:
	@esy b jbuilder build -j 4 $(TARGETS)

build-dev:
	@esy b jbuilder build -j 4 --dev $(TARGETS)

refmt:
	@find esy esy-build-package -name '*.re' | xargs -n1 esy refmt --in-place

#
# Test
#

JEST = $(BIN)/jest --runInBand

test-unit::
	@esy b jbuilder build --dev @runtest

test-e2e::
	@make -C test-e2e test

test-opam::
	$(MAKE) -C __tests__/opam

ci::
	@$(MAKE) test-unit
	@$(MAKE) test-e2e

test::
	@$(MAKE) test-unit
	@$(MAKE) test-e2e

#
# Release
#

RELEASE_ROOT = _release
RELEASE_FILES = \
	bin/esy \
	bin/esy-install.js \
	scripts/postinstall.sh \
	package.json \
	_build-darwin/default/esy-build-package/bin/esyBuildPackageCommand.exe \
	_build-darwin/default/esy/bin/esyCommand.exe \
	_build-linux/default/esy-build-package/bin/esyBuildPackageCommand.exe \
	_build-linux/default/esy/bin/esyCommand.exe

build-release:
	@$(MAKE) build
	@$(MAKE) -C linux-build build
	@$(MAKE) build-release-copy-artifacts

build-release-copy-artifacts:
	@rm -rf $(RELEASE_ROOT)
	@$(MAKE) -j $(RELEASE_FILES:%=$(RELEASE_ROOT)/%)

$(RELEASE_ROOT)/_build-darwin/default/esy/bin/esyCommand.exe:
	@mkdir -p $(@D)
	@cp _build/default/esy/bin/esyCommand.exe $(@)

$(RELEASE_ROOT)/_build-darwin/default/esy-build-package/bin/esyBuildPackageCommand.exe:
	@mkdir -p $(@D)
	@cp _build/default/esy-build-package/bin/esyBuildPackageCommand.exe $(@)

$(RELEASE_ROOT)/_build-linux/default/esy/bin/esyCommand.exe:
	@mkdir -p $(@D)
	@cp linux-build/esyCommand.exe $(@)

$(RELEASE_ROOT)/_build-linux/default/esy-build-package/bin/esyBuildPackageCommand.exe:
	@mkdir -p $(@D)
	@cp linux-build/esyBuildPackageCommand.exe $(@)

$(RELEASE_ROOT)/bin/esy-install.js:
	@$(MAKE) -C esy-install BUILD=../$(@) build

$(RELEASE_ROOT)/%: $(PWD)/%
	@mkdir -p $(@D)
	@cp $(<) $(@)

publish: build-release
	@(cd $(RELEASE_ROOT) && npm publish --access public --tag $(RELEASE_TAG))
	@git push && git push --tags

bump-major-version:
	@npm version major

bump-minor-version:
	@npm version minor

bump-patch-version:
	@npm version patch
