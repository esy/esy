---
id: getting-started
title: Getting started
---

esy provides a single command called `esy` that can be invoked inside of any
directory containing a `package.json` file. The typical workflow is to `cd`
into a directory that contains a `package.json` file, and then perform
operations on that project.


When running `esy` commands in that directory, `esy` creates and manages
isolated build environment for your package called a "sandbox".
Each sandbox, in each directory is isolated from every other sandbox.

Here are two example projects:

- [hello-reason](https://github.com/esy-ocaml/hello-reason), an example Reason
  project which uses [dune][] build system.
- [hello-ocaml](https://github.com/esy-ocaml/hello-ocaml), an example OCaml
  project which uses [dune][] build system.


## Install esy

```shell
npm install -g esy
```

If you had installed esy previously:

```shell
npm uninstall --global --update esy
```

## Clone & initialize the project

Clone the project source code

```shell
git clone https://github.com/esy-ocaml/hello-reason.git
cd hello-reason
```

Install project's dependencies source code and perform an initial build of the
project's dependencies and of the project itself:

```shell
esy
```

## Run compiled executables

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

This will take care of updating dependencies as well as building the project. Same as running `esy install` and `esy build` sequentially.

If you're sure, dependencies haven't been updated, simply run `esy build`

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
