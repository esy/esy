SRC = $(shell find src -name '*.re')

build:
	@esy build

refmt:
	@$(MAKE) -j 4 $(SRC:%.re=%.re.refmt)

%.re.refmt: %.re
	@esy refmt --in-place --print-width 80 $(<)
