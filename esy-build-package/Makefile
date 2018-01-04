install:
	@esy install

build:
	@esy build
	@esy ocamlstripdebug _build/default/bin/esyBuildPackage.bc _build/esyBuildPackage

build-dev:
	@esy b jbuilder build --dev
