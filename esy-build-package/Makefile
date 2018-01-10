install:
	@esy install

build:
	@esy build
	@esy ocamlstripdebug _build/default/esy-build-package/esyBuildPackage.bc _build/esyBuildPackage

build-dev:
	@esy b jbuilder build --dev

clean:
	@rm -rf _build
