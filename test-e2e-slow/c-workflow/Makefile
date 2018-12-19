build:
	cc $(shell pkg-config --cflags --libs dep) -o $(cur__target_dir)/main main.c

install:
	cp $(cur__target_dir)/main $(cur__install)/bin/main
