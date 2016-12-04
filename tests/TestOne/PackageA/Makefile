SHELL=/bin/bash

build: node_modules
	@$(MAKE) -f <(../../../.bin/esy build) PackageA

node_modules:
	sh ./test.sh

clean:
	rm -rf _build _install
