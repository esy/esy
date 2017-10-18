BIN = $(PWD)/node_modules/.bin

#
# Tools
#

.DEFAULT: help

help:
	@echo "Available tasks:"
	@echo ""
	@echo "  bootstrap       Initialize development environment"
	@echo ""
	@echo "  build           Build src/ into lib/"
	@echo "  build-watch     Same as 'build' but watches for changes and rebuilds"
	@echo "  test            Run tests"
	@echo "  test-watch      Watch for changes and re-run tests"
	@echo "  clean           Clean build artefacts"
	@echo ""

bootstrap:
	@yarn
	@(cd esy-install && yarn && yarn build)

build:
	@$(BIN)/babel ./src --copy-files --out-dir ./lib

build-watch:
	@$(BIN)/babel --copy-files --watch -s inline ./src --out-dir ./lib

test-watch:
	@ESY__TEST=yes $(BIN)/jest --watch

test:
	@ESY__TEST=yes $(BIN)/jest

clean:
	@rm -rf lib/

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
