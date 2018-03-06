.DELETE_ON_ERROR:

INPUT_DIR = /tmp/esy-linux-build-input
OUTPUT_DIR = /tmp/esy-linux-build-output

prepare:
	@echo "linux-build: packing sources tarball..."
	@rm -rf $(INPUT_DIR) $(OUTPUT_DIR)
	@mkdir $(INPUT_DIR) $(OUTPUT_DIR)
	@(cd ../ && git archive -o $(PWD)/src.tar.gz HEAD .)
	@mv $(PWD)/src.tar.gz $(INPUT_DIR)/src.tar.gz
	@cp Makefile $(INPUT_DIR)/Makefile

docker-image-id:
	@echo "linux-build: preparing docker image..."
	@docker build -q . > $(@)

esy: prepare docker-image-id
	@echo "linux-build: running build in docker container..."
	@docker run \
		--volume $(HOME)/.esy-linux:/root/.esy \
		--volume $(INPUT_DIR):/src \
		--volume $(OUTPUT_DIR):/out \
		-it $(shell cat docker-image-id) bash -c 'cd /src && make build-on-target'
	@cp $(OUTPUT_DIR)/esyCommand.exe ./
	@cp $(OUTPUT_DIR)/esyBuildPackageCommand.exe ./

build: esy

clean:
	@rm -rf esyCommand.exe esyBuildPackageCommand.exe

build-on-target:
	@tar -xzf src.tar.gz
	@esy install
	@esy build
	@cp _build/default/esy/bin/esyCommand.exe /out/esyCommand.exe
	@cp _build/default/esy-build-package/bin/esyBuildPackageCommand.exe /out/esyBuildPackageCommand.exe
