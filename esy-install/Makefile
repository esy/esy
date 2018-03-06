.DELETE_ON_ERROR:

BUILD ?= dist/esy-install.js

.PHONY: bootstrap
bootstrap:
	@yarn

.PHONY: build
build: $(BUILD)

.PHONY: clean
clean:
	@git clean -fdx .

$(BUILD):
	@node ./scripts/build-webpack.js ./src/bin/esy.js $(@)
