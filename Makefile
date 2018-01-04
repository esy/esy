RELEASE_TAG ?= latest
BIN = $(PWD)/node_modules/.bin

#
# Tools
#

.DEFAULT: help

define HELP

 Available tasks:

   bootstrap           Bootstrap the development environment

   build               Build src/ into lib/
   build-watch         Same as 'build' but watches for changes and rebuilds

   test                Run tests
   test-watch          Watch for changes and re-run tests

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
	@yarn

doctoc:
	@$(BIN)/doctoc --notitle ./README.md

#
# Build
#

build:
	@$(BIN)/babel ./src --copy-files --out-dir ./lib

build-watch:
	@$(BIN)/babel --copy-files --watch -s inline ./src --out-dir ./lib

clean:
	@rm -rf lib/

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

#
# Release
#

RELEASE_ROOT = $(PWD)/dist
RELEASE_FILES = \
	bin/esy \
	bin/esyBuildRelease \
	bin/esyBuildPackage \
	bin/esyExportBuild \
	bin/esyImportBuild \
	bin/esyRuntime.sh \
	bin/realpath.sh \
	scripts/postinstall.sh

build-release:
	@rm -rf $(RELEASE_ROOT)
	@$(MAKE) $(RELEASE_FILES:%=$(RELEASE_ROOT)/%)
	@node ./scripts/build-webpack.js ./dist/bin
	@node ./scripts/generate-esy-install-package-json.js > $(RELEASE_ROOT)/package.json

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
