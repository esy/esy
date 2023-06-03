---
id: c-workflow
title: "Workflow for C/C++ Packages"
---

esy providing a workflow for native development couldn't skip supporting C/C++
packages as C/C++ libraries/tools are so widespread.

There are numerous examples of Reason/OCaml code using C/C++ code via FFI:
bindings to libcurl, SDL, OpenGL and so on and so on.

The easiest way to expose some C/C++ code between esy packages is with
[pkg-config][].

## Exposing C library with pkg-config

Let's consider a C library called `dep` which is going to be consumed as an
`dep` esy package.

First we need to write `dep.pc` file which contains pkg-config configuration
file for our lib.

We do this via `Makefile` with `build` and `install` targets:

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
      ... build commands ...

    install:
      ... other install commands ...
      echo "$$dep_pc" > $(cur__install)/lib/dep.pc

Note that we have installed out `dep.pc` into `$cur__install/lib`, we need to
update `$PKG_CONFIG_PATH` with this in `"esy.exportedEnv"`:

    {
      "name": "dep",
      "version": "1.0.0",
      "esy": {
        "build": "make build",
        "install": "make install",
        "exportedEnv": {
          "PKG_CONFIG_PATH": {
            "val": "#{self.lib : $PKG_CONFIG_PATH}",
            "scope": "global"
          }
        }
      }
    }

In the `package.json` above `#{self.lib}` is the same value as
`$cur__install/lib` but represented via esy's command expression syntax.

> **NOTE**
>
> If you are porting some C/C++ library into esy then it is most likely this
> library already has `*.pc` file present. Then you need only to make sure you
> update `$PKG_CONFIG_PATH` in the `package.json` corresponding to the library.

## Consuming C library with pkg-config

To link a C library exposed with `pkg-config` a project must depend on that
library and on `pkg-config` package which is hosted on GitHub at
[esy-packages/pkg-config][].

The entire `package.json` for the project would look like this:

    {
      "name": "my-project",
      "esy": {
        "build": "make build",
        "install": "make install"
      },
      "dependencies": {
        "dep": "1.0.0",
        "pkg-config": "esy-packages/pkg-config"
      }
    }

The `Makefile` will contain a call to `pkg-config` to generate command line
options for C compiler needed to compile against a library `dep` and link it to
the final executable:

    build:
      cc $(shell pkg-config --cflags --libs dep) \
         -o $(cur__target_dir)/main main.c

This is the entire workflow needed to work with C/C++ code with esy.

[pkg-config]: https://www.freedesktop.org/wiki/Software/pkg-config/
[esy-packages/pkg-config]: https://github.com/esy-packages/pkg-config
