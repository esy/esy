INPUT_DIR = /tmp/esy-linux-build-input
OUTPUT_DIR = /tmp/esy-linux-build-output

prepare:
	rm -rf $(INPUT_DIR) $(OUTPUT_DIR)
	mkdir $(INPUT_DIR) $(OUTPUT_DIR)
	(cd ../ && git archive -o $(PWD)/src.tar.gz HEAD esy-core)
	mv $(PWD)/src.tar.gz $(INPUT_DIR)/src.tar.gz
	cp Makefile $(INPUT_DIR)/Makefile

docker-image-id:
	@docker build -q . > $(@)

esy: prepare docker-image-id
	@docker run \
		--volume $(INPUT_DIR):/src \
		--volume $(OUTPUT_DIR):/out \
		-it $(shell cat docker-image-id) bash -c 'cd /src && make build-on-target'
	@cp $(OUTPUT_DIR)/esy ./
	@cp $(OUTPUT_DIR)/esyBuildPackage ./

build: esy

clean:
	@rm -rf esy esyBuildPackage

build-on-target:
	tar -xzf src.tar.gz
	(cd esy-core && esy install)
	(cd esy-core && esy build)
	cp esy-core/_build/default/esy/bin/esyCommand.exe /out/esy
	cp esy-core/_build/default/esy-build-package/bin/esyBuildPackageCommand.exe /out/esyBuildPackage
