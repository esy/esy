install:
	@esy install

build-dev:
	@esy b jbuilder build --dev

build:
	@esy build

DIST_FILES=esyb.bc package.json README.md postinstall.sh

dist::
	@$(MAKE) build
	rm -rf dist
	mkdir dist
	@$(MAKE) $(DIST_FILES:%=dist/%)
	touch dist/esyb

publish: dist
	cd dist && npm publish

dist/esyb.bc: _build/default/bin/esyb.bc
	esy ocamlstripdebug _build/default/bin/esyb.bc dist/esyb.bc

dist/%: %
	cp $(<) $(@)
