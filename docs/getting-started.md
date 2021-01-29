---
id: getting-started
title: Getting started
---

esy provides a single command called `esy` that can be invoked inside of any
directory containing a `package.json` file. The typical workflow is to `cd`
into a directory that contains a `package.json` file, and then perform
operations on that project.


## Install esy

```shell
npm install -g esy
```

If you had installed esy previously:

```shell
npm uninstall --global --update esy
```

## Step-by-step tutorial

To understand the benefits and general workflow of writing a program with esy, we put together a simple Step-by-Step guide for you to follow.
In this guide we want to write a simple "Hello, World" program. It will just print "Hello, World" to the console and exit afterwards.

If you have questions or you find yourself stuck anywhere, don't hesitate to reach out at one of our [community platforms](https://esy.sh/docs/en/community.html)

Let's start with an empty `package.json`

```json
{}
```

Every program we may want to write with ReasonML or OCaml needs at least the OCaml compiler as a dependency.

```json
{
  "dependencies": {
    "ocaml": "4.10.x"
  }
}
```

And our OCaml source file, `hello.ml` with 

```ml
let () = print_endline "Hello, World"
```

To install the dependencies, run `esy`

```sh
$ esy
```

This will fetch all of our dependencies (at this point, just `ocaml`) and install it in a sandbox exclusively created for this project.

A esy sandbox is like an isolated environment for your project, so everything you install is just installed inside this environment and not globally on your system.

The advantage of a sandbox is that different projects can have different versions of the same dependency installed, which would not be easily possible if they were just installed globally.

In OCaml, we can't just run our code as with for example NodeJS. It first needs to be compiled to an executable with the OCaml compiler we installed previously.

The compiler gets invoked with either the command `ocamlopt` (for native compilation) or `ocamlc` (for bytecode compilation). You can learn more about the compilers here. In this example, we will prodeed with the native compiler (ocamlopt). The most basic syntax for compiling a file to an executable looks like this: `ocamlopt -o <output.exe> <source-file>`.

With this info at hand, our first instinct might be just running `ocamlopt -o hello.exe hello.ml` to produce our executable file. But remember, we didn't install ocaml globally, but in our projects sandbox. So we need to somehow run this command inside of this sandbox.

Just like in the Yarn/NPM world, build commands are run with a prefix.

To compile,

```sh
esy ocamlopt -o hello.exe hello.ml
```

If everything worked correctly, running the command above should have output a file called hello.exe.
To now execute our program and output "Hello, World", we just need to run:

```sh
./hello.exe
```

If you are following along on a Mac or Linux, it might seem a bit odd, that you can run an .exe file, as these files normally can only be run on Windows systems. This is just for convenience and completely optional.


### Using a build system

Compiling your code with ocamlopt or ocamlc works well, when you don't have a lot of dependencies. But as soon as your project gets larger, compiling your code manually becomes very complex, very fast. To help with this, we want to use a build system.

If you are coming from JavaScript, you probably already heard from tools like "Webpack", "Browserify" or "Rollup". These are build systems. They take your code and its dependencies and bundle them together into a single file.

For Reason and OCaml, we use [Dune](https://dune.readthedocs.io/en/stable/) - the community endorsed build system. You give it an entry point and it "bundles" all of your code and its dependencies together into a single executable.

To install dune into our "Hello World" program, we have to add `@opam/dune` to the dependencies of our package.json.


```diff
  "dependencies": {
    "ocaml": "4.10.x",
+   "@opam/dune": "*"
  }
```

If you're familiar with Dune, you'd know, that starting from scratch, Dune
needs

1. A `dune-project` file describe the project
2. A `dune` file to describe the binary being compiled
3. An opam file (say `hello.opam`) to so that Dune can assign the
   project an identifier.
   

1. Create an empty file `hello.opam`. This file assigns the namespace
   `hello` to our package among the set of libraries.
2. Create a `dune` file to describe how the program. Mostly, just it's
   public name and the file creating it
   
   ```
   (executable
     (name hello) ; asking dune to build hello.ml
	   (public_name hello.exe)) ; name of the binary
   ```
   
   We're now ready to build and distribute the hello world program.

3. Optionally, create a `dune-project` file. If you don't, Dune will
   create it for you.

```
(lang dune 2.7)
(name hello)
```

1. `lang` specifies the configuration language version. Yes! Dune
   configuration language is versioned which brings extra stability!
2. `name` specifies the identifier for the project. This has to be
   same as the opam file name.
   
As with the compilation of single program, you might expect to prefix
Dune's build command, `dune build`, with `esy` and expect things to
work.

```sh
esy dune build
```

You're not wrong.

However, esy's real strength is isolated build environment - read the
`package.json`, create an isolated environment, try to build the project
there. 

This way, should you happen to forget to include a dependency in your
package.json, the build will break. Other package managers don't guarantee
this! Esy also creates lock files, not optional like in `opam`. This
ensures users have the same version of a dependency across machines.

To build projects in isolated build environments, use `esy b` prefix.

```sh
esy b dune build
```

You can now find the files Dune usually creates under `_build`
directory at `_esy/default/build`. Run the binary with,

```sh
./_esy/default/build/default/hello.exe
```

You can think of it as `./_esy/{your esy sandbox name}/build/{your dune profile}/hello.exe`

Alternatively,

```sh
esy b dune exec ./hello.exe
```

### Out of source
It, indeed, was very convenient to have the binary, `hello`, created
right next to the source file, `hello.ml`. As they'd say, in-source
compilation. 

In real world applications, such binaries are rarely run directly. For
two reasons,

1. They are installed in a global location somewhere else. Like
   `/usr/local`, `/usr/bin`
2. Running them directly (`$ /path/to/hello.exe`) is rarely reliable
   as they might depend on a version of libary that simply may not be
   present, or the wrong version.
   
Just like build environments, it would be nice to our project binaries
in a special environment where the binaries and libraries project
needs is available in the exact version needed and isolated from what
the rest of the machine.

Esy provides just that - we call it the exported environment.

We need to 

1. Install the binary
2. Call this binary from the exported environment.


By install, we mean installing it to a location local to the project,
but for all intents and purposes, it behaves like as it it were a
global location. A virtualised environment. 

To do so, tweak the build command to ask Dune to not just compile, to
generate some special files that would help in installing the
binary.

```
esy b dune build -p hello
```

To run the binary in the exported environment, one would have to build
and then run the install command in sequence.

```
esy b dune build -p hello && esy b dune install # Only for illustration. Not a valid command
```

This would, theoretically, install the binary in a project local sandbox and make it
available in the exported environment.

We instead recommend, specifying the build command, `dune build -p
hello`, in the package.json.


```diff
{
+  "esy": {
+    "build": "dune build -p hello"
+  },
  "dependencies": {
    "ocaml": "4.10.x",
	"@opam/dune": "*"
  }
}
```

Esy understands Dune, and the following will not be necessary

```diff
  "esy": {
    "build": "dune build -p hello",
-   "install": "dune install"
  },
```

With the final package.json looking like this,
```
{
  "esy": {
    "build": "dune build -p hello"
  },
  "dependencies": {
    "ocaml": "4.10.x",
    "@opam/dune": "*"
  }
}
```

The command to build the project simply becomes, `esy` 

```
$ esy
info esy 0.6.8 (using package.json)
info fetching: done
info installing: done                                
Done: 13/17 (jobs: 1)
$
```

To check if the built project would install and run fine, instead of a
command like `esy b <run install command> && ./path/to/hello.exe`, we
can simply run,

```sh
esy x hello.exe
```

ie. prepending `esy x` to the final command the user of the tool expects
it. If the tool is invoked on the deployed machine as `$ mytool
--option1 --option2`, you can test it during development in it's
exported environment as `$ esy x mytool --option1 --option2`.

That's it!

We have a template, [hello-reason](https://github.com/esy-ocaml/hello-reason) ready for you to help you quickly get started.

```shell
git clone https://github.com/esy-ocaml/hello-reason.git
cd hello-reason
esy
```

## Cheat sheet

### Install dependencies

Make sure the package.json has the dependencies specified. Then run,
```
esy install
# or
esy i
# or simply
esy
```

### Build
Make sure the package.json as the build command specified. And then,

```sh
esy build
# or
esy b
# or simply
esy
```

### Run compiled executables

Use `esy x COMMAND` invocation to run project's built executable as if they are
installed:

```shell
esy x Hello
```

### Where is the binary executable?
When a compiled binary is run with `esy x Hello`, esy creates a local install sandbox with `/bin`, `/lib`, `/etc` and other directories found globally where binaries are meant to be installed. If you're curious, you could peek into them, running

```shell
esy echo #{self.install}
```

and inspect the contents yourself. You'll find the binaries in the `bin` directory.

However, they are not meant to be run directly as they could be missing the necessary [exported environment](./concepts.md) - it could be possible that the binary you created needs a dependency during the runtime. `esy x <your project binary>` is the recommended way to run them.

Checkout [concepts](./concepts.md) for more information.

## Rebuild the project

Hack on project's source code and rebuild the project:

```shell
esy 
```

## Adding a dependency

```shell
esy add <dependency>
```

This will fetch the sources and copy them in esy's store. Next, run

```shell
esy build
```

This will build the newly downloaded dependency.

Alternatively, add a new entry in the `dependencies` (or `devDependencies`) 

```diff
  "@reason-native/console: "*"
+ "@reason-native/pastel": "*"
  "@reason-native/rely": "*"
```

And run, esy afterwards.

## Other useful commands

It is possible to invoke any command from within the project's sandbox.  For
example build & run tests with:

```shell
esy make test
```

You can run any `COMMAND` inside the project development environment by just
prefixing it with `esy`:

```shell
esy COMMAND
```

To shell into the project's development environment:

```shell
esy shell
```

For more options:

```shell
esy help
```


[dune]: https://github.com/ocaml/dune
