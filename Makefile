SRC = $(shell find src -type f)
LIB = $(SRC:src/%=lib/%)

convert-opam-packages:
	@$(MAKE) -C opam-packages-conversion/ convert
	@rm -rf opam-packages/
	@mv opam-packages-conversion/output opam-packages

prepare-release: build

build:
	@$(MAKE) -j $(LIB)

release: build
	@rm -rf .tmp
	@mkdir .tmp
	@mv node_modules/ .tmp/node_modules
	@npm install --production --ignore-scripts
	@mv node_modules lib/node_modules;
	@cp package.json .tmp/package.json
	@node ./scripts/rewriteDependencies.js
	@npm publish --access public
	@cp .tmp/package.json package.json
	@mv .tmp/node_modules node_modules
	@rm -rf lib/node_modules

clean:
	@rm -rf lib/

lib/%.js: src/%.js
	@mkdir -p $(@D)
	@babel -o $@ $<

lib/%: src/%
	@mkdir -p $(@D)
	@cp $< $@
