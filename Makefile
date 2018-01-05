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
	@make -C esy-build-package install build
	@yarn

doctoc:
	@$(BIN)/doctoc --notitle ./README.md

clean:
	@rm -rf lib/
	@make -C esy-build-package clean

#
# Test
#

test-unit:
	@$(BIN)/jest src/

test-unit-watch:
	@$(BIN)/jest src/ --watch

test-esy-release:
	@$(BIN)/jest ./__tests__/release/*-test.js

test-esy-build:
	@$(BIN)/jest ./__tests__/build/*-test.js

test-e2e:
	(cd __tests__ && bash symlink-workflow-test.sh)

test-opam:
	(cd __tests__ && bash opam-test.sh)

test:
	@$(BIN)/jest \
		./src/__tests__ \
		./__tests__/build/*-test.js \
		./__tests__/release/*-test.js \
		./__tests__/export-import-build/*-test.js
	$(MAKE) test-e2e

ci:
	@$(BIN)/jest \
		--runInBand \
		./src/__tests__ \
		./__tests__/build/*-test.js \
		./__tests__/release/*-test.js \
		./__tests__/export-import-build/*-test.js
	$(MAKE) test-e2e
	$(MAKE) test-opam

#
# Release
#

RELEASE_ROOT = dist
RELEASE_FILES = \
	bin/esy \
	bin/esy.js \
	bin/esyBuildPackage \
	bin/esyExportBuild \
	bin/esyImportBuild \
	bin/esyRuntime.sh \
	bin/realpath.sh \
	scripts/postinstall.sh \
	package.json

build-release:
	@rm -rf $(RELEASE_ROOT)
	@$(MAKE) -j $(RELEASE_FILES:%=$(RELEASE_ROOT)/%)

$(RELEASE_ROOT)/package.json:
	@node ./scripts/generate-esy-install-package-json.js > $(@)

$(RELEASE_ROOT)/bin/esy.js:
	@node ./scripts/build-webpack.js ./src/bin/esy.js $(@)

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
