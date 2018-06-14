.DELETE_ON_ERROR:

ESY_EXT := $(shell command -v esy 2> /dev/null)

RELEASE_TAG ?= latest
BIN = $(PWD)/node_modules/.bin
PROJECTS = esy esy-build-package esyi

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

 Other tasks:

   refmt               Reformal all *.re source with refmt

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
	@esy install
	@make -C esy-install bootstrap
	@make build-dev
	@make -C test-e2e bootstrap
	@make -C test-e2e/pkg-tests bootstrap
	@ln -s $$(esy which fastreplacestring) $(PWD)/bin/fastreplacestring

doctoc:
	@$(BIN)/doctoc --notitle ./README.md

clean:
	@esy jbuilder clean

build:
	@esy b jbuilder build -j 4 $(TARGETS)

b: build-dev
build-dev:
	@esy b jbuilder build -j 4 --dev $(TARGETS)

#
# Test
#

JEST = $(BIN)/jest --runInBand

test-unit::
	@esy b jbuilder build --dev @runtest

test-e2e::
	@make -C test-e2e test

test-e2e-esyi::
	@make -C test-e2e/pkg-tests test

test-opam::
	$(MAKE) -C __tests__/opam


test::
	@echo "Running test suite: unit tests"
	@$(MAKE) test-unit
	@echo "Running test suite: e2e"
	@$(MAKE) test-e2e
	@echo "Running test suite: e2e installer"
	@$(MAKE) test-e2e-esyi

ci:: test

#
# Release
#

RELEASE_ROOT = _release
RELEASE_FILES = \
	bin/esy \
	bin/fastreplacestring-darwin \
	bin/fastreplacestring-linux \
	bin/esy-install.js \
	bin/esyInstallRelease.js \
	scripts/postinstall.sh \
	package.json \
	_build/default/esy-build-package/bin/esyBuildPackageCommand-darwin.exe \
	_build/default/esyi/bin/esyi-darwin.exe \
	_build/default/esy/bin/esyCommand-darwin.exe \
	_build/default/esy-build-package/bin/esyBuildPackageCommand.exe \
	_build/default/esyi/bin/esyi.exe \
	_build/default/esy/bin/esyCommand.exe \
	_build/default/esy-build-package/bin/esyBuildPackageCommand-linux.exe \
	_build/default/esyi/bin/esyi-linux.exe \
	_build/default/esy/bin/esyCommand-linux.exe

build-release:
	@$(MAKE) build
	@$(MAKE) -C linux-build build
	@$(MAKE) build-release-copy-artifacts

build-release-copy-artifacts:
	@rm -rf $(RELEASE_ROOT)
	@$(MAKE) -j $(RELEASE_FILES:%=$(RELEASE_ROOT)/%)

$(RELEASE_ROOT)/_build/default/esy/bin/esyCommand-darwin.exe:
	@mkdir -p $(@D)
	@cp _build/default/esy/bin/esyCommand.exe $(@)

$(RELEASE_ROOT)/_build/default/esy-build-package/bin/esyBuildPackageCommand-darwin.exe:
	@mkdir -p $(@D)
	@cp _build/default/esy-build-package/bin/esyBuildPackageCommand.exe $(@)

$(RELEASE_ROOT)/_build/default/esyi/bin/esyi-darwin.exe:
	@mkdir -p $(@D)
	@cp _build/default/esyi/bin/esyi.exe $(@)

$(RELEASE_ROOT)/_build/default/esy/bin/esyCommand-linux.exe:
	@mkdir -p $(@D)
	@cp linux-build/esyCommand.exe $(@)

$(RELEASE_ROOT)/_build/default/esy-build-package/bin/esyBuildPackageCommand-linux.exe:
	@mkdir -p $(@D)
	@cp linux-build/esyBuildPackageCommand.exe $(@)

$(RELEASE_ROOT)/_build/default/esyi/bin/esyi-linux.exe:
	@mkdir -p $(@D)
	@cp linux-build/esyi.exe $(@)

$(RELEASE_ROOT)/bin/fastreplacestring-linux:
	@mkdir -p $(@D)
	@cp linux-build/fastreplacestring.exe $(@)

$(RELEASE_ROOT)/_build/default/esy/bin/esyCommand.exe:
	@mkdir -p $(@D)
	@touch $(@)

$(RELEASE_ROOT)/_build/default/esy-build-package/bin/esyBuildPackageCommand.exe:
	@mkdir -p $(@D)
	@touch $(@)

$(RELEASE_ROOT)/_build/default/esyi/bin/esyi.exe:
	@mkdir -p $(@D)
	@touch $(@)

$(RELEASE_ROOT)/bin/esy-install.js:
	@$(MAKE) -C esy-install BUILD=../$(@) build

$(RELEASE_ROOT)/bin/fastreplacestring-darwin:
	@mkdir -p $(@D)
	@cp $$(esy which fastreplacestring) $(@)

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

refmt::
	@find $(PROJECTS) -name '*.re' \
		| xargs -n1 esy refmt --in-place --print-width 80
