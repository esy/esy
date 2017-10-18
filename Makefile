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

 Release tasks:"

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
	@yarn

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

test:
	@ESY__TEST=yes $(BIN)/jest

test-watch:
	@ESY__TEST=yes $(BIN)/jest --watch

test-esy-release:
	@echo "Running integration tests for 'esy release' command"
	@$(BIN)/jest --runInBand ./__tests__/release/*-test.js

#
# Release
#

RELEASE_ROOT = $(PWD)/dist

build-release:
	@rm -rf $(RELEASE_ROOT)
	@mkdir -p $(RELEASE_ROOT)
	@mkdir -p $(RELEASE_ROOT)/bin
	@cp $(PWD)/bin/esy $(RELEASE_ROOT)/bin/
	@node ./scripts/build-webpack.js ./dist/bin
	@node ./scripts/generate-esy-install-package-json.js > $(RELEASE_ROOT)/package.json

publish: build-release
	@(cd $(RELEASE_ROOT) && npm publish --access public)

bump-version:
ifndef BUMP_VERSION
	@echo 'Provide BUMP_VERSION=major|minor|patch, exiting...'
	@exit 1
endif
	@npm version $(BUMP_VERSION)
