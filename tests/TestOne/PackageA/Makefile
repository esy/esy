SHELL=/bin/bash

build: node_modules
	@$(MAKE) \
		-f <(../../../.bin/esy build) \
		ESY_DYNAMICALLY_SET_ME_TO_SANDBOX_ROOT_ON_HOST=$(PWD) PackageA

node_modules:
	sh ./test.sh

clean:
	rm -rf _build _install
