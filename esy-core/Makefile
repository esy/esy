TARGETS = \
	esy-build-package/bin/esyBuildPackage \
	esy/bin/esy

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
	@rm -rf _build
