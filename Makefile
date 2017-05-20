BIN = $(PWD)/node_modules/.bin

#
# Tools
#

.DEFAULT: help

help:
	@echo "Available tasks:"
	@echo ""
	@echo "  build           Build src/ into lib/"
	@echo "  build-watch     Same as 'build' but watches for changes and rebuilds"
	@echo "  test            Run tests"
	@echo "  test-watch      Watch for changes and re-run tests"
	@echo "  clean           Clean build artefacts"
	@echo ""

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

#
# Release
#
