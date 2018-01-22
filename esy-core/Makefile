install:
	@esy install

build:
	@esy build
	@$(MAKE) postbuild

postbuild:
	@esy ocamlstripdebug _build/default/esy-build-package/esyBuildPackage.bc _build/esyBuildPackage

build-dev:
	@esy b jbuilder build --dev

.PHONY: test
test:
	@esy b jbuilder build @runtest

clean:
	@rm -rf _build
