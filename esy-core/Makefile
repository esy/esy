TARGETS = \
	esy-build-package/bin/esyBuildPackageCommand.exe \
	esy/bin/esyCommand.exe

.DEFAULT: help

define HELP

 Run "make bootstrap" if you are not sure, then go edit esy source code
 with "esy vim ./path/to/source.re".

 Common tasks:

   bootstrap           Bootstrap the development environment
   test                Run tests
   clean               Clean build artefacts
   build-dev           Incrememental dev build (more warning enabled)
   build               Release build
   help                Show this message.

endef
export HELP

help:
	@echo "$$HELP"

bootstrap:
	@$(MAKE) install build-dev

install:
	@esy install

build:
	@esy b jbuilder build -j 4 $(TARGETS)

build-dev:
	@esy b jbuilder build -j 4 --dev $(TARGETS)

.PHONY: test
test:
	@esy b jbuilder build --dev @runtest

clean:
	@rm -rf _build node_modules/.cache/
