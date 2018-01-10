#!/bin/bash

source ./testlib.sh
source ./setup.sh

initFixture opam-test

run esy install
run esy build
