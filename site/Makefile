MAKEFILE_PATH := $(abspath $(firstword $(MAKEFILE_LIST)))
PROJECT_DIR := $(shell dirname $(MAKEFILE_PATH))

BIN = $(PROJECT_DIR)/node_modules/.bin

GIT_USER ?= $(USER)

bootstrap::
	@yarn --pure-lockfile

build::
	@$(BIN)/docusaurus-build

publish::
	@GIT_USER=$(GIT_USER) USE_SSH=true $(BIN)/docusaurus-publish

start::
	@$(BIN)/docusaurus-start
