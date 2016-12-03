build: Makefile.esy node_modules
	@$(MAKE) \
		-f ./Makefile.esy \
		ESY_DYNAMICALLY_SET_ME_TO_SANDBOX_ROOT_ON_HOST=$(PWD) PackageA

node_modules:
	sh ./test.sh

clean:
	rm -rf _build _install

Makefile.esy:
	@../../../.bin/esy build > $@

