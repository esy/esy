---
id: getting-started
title: Getting started
---

Esy provides a single command called `esy`.

The typical workflow is to `cd` into a directory that contains a `package.json`
file, and then perform operations on that project.

### Try An Example

There are example projects:

* [OCaml + jbuilder project](https://github.com/esy-ocaml/esy-ocaml-project)
* [Reason + jbuilder project](https://github.com/esy-ocaml/esy-reason-project)

The typical workflow looks like this:

0. Install esy:

   ```bash
   npm install -g esy
   ```

   If you had installed esy previously:

   ```bash
   npm uninstall --global --update esy
   ```

1. Clone the project:

   ```bash
   git clone git@github.com:esy-ocaml/esy-ocaml-project.git
   cd esy-ocaml-project
   ```

1. Install project's dependencies source code:

   ```bash
   esy install
   ```

1. Perform an initial build of the project's dependencies and of the project
   itself:

   ```bash
   esy build
   ```

1. Test the compiled executables inside the project's environment:

   ```bash
   esy ./_build/default/bin/hello.exe
   ```

1. Hack on project's source code and rebuild the project:

   ```bash
   esy build
   ```

Also:

6. It is possible to invoke any command from within the project's sandbox.
   For example build & run tests with:

   ```shell
   esy make test
   ```

   You can run any command inside the project environment by just
   prefixing it with `esy`:

   ```bash
   esy <anycommand>
   ```

7. To shell into the project's sandbox:

   ```bash
   esy shell
   ```

8. For more options:

   ```bash
   esy help
   ```
