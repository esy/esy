define dep_pc
prefix=$(cur__install)
exec_prefix=$${prefix}
includedir=$${prefix}/lib
libdir=$${exec_prefix}/lib

Name: dep
Description: The dep library
Version: 1.0.0
Cflags: -I$${includedir}
Libs: -L$${libdir} -ldep
endef
export dep_pc

build:
	gcc -o $(cur__target_dir)/dep.o -c ./dep.c
	ar -rcs $(cur__target_dir)/libdep.a $(cur__target_dir)/dep.o

install:
	cp $(cur__target_dir)/libdep.a $(cur__install)/lib/libdep.a
	cp $(cur__root)/dep.h $(cur__install)/lib/dep.h
	echo "$$dep_pc" > $(cur__install)/lib/dep.pc
