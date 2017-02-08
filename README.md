# esy
Easy Sandboxes For Compiled Languages
-------------------------------------

## Install

`npm install -g "git://github.com/jordwalke/esy.git#beta-v0.0.2"`

### About

Rough sketch start of implementation for
[PackageJsonForCompilers](https://github.com/jordwalke/PackageJsonForCompilers)
concept. (Here, the name is `esy` instead of `pjc`).

`esy` seeks to support an "eject" feature, which makes
`PackageJsonForCompilers` easy to deploy/build on hosts that don't even have
node installed - they would only need `make`. Just copy the entire sandbox over
to the host and run the makefile.

The `esy` command (without anything following the `esy` word), prints the
environment for *one package*, taking into account variables exported by
dependencies. The final goal of the `esy build` command is to walk the entire
dependency graph, running their `build` commands, and running each dependency's
`build` command in an environment computed from the `esy` command, for that
one package.

The environments computed by `esy` are with respect to (sandbox root, `cur`
package), where the sandbox root is the top level package we're building
everything for, and `cur` package is one of the transitive dependencies.
Running `esy` in a directory is like printing the environment as if `pwd` was
both the sandbox root *and* the "currently building package".

The `esy build` command would walk the tree with `sandbox root = topmost package`,
and at each node set `cur package = <THIS_DEPENDENCY>`, and run the build command
in an environment computed based on that combination.

We'd want to generate a makefile that encodes the graph of packages, and can build
everything with maximum parallelism.


#### Test

Built In Commands

|Command                  | Meaning                                                                                               | Implemented |
|-------------------------|------------------------------------------------                                                       |-------------|
|`esy`                    | Print the environment variables for current directory as sandbox root and `cur` root.                 | Started     |
|`esy build`              | Implements `pjc build` command from `PackageJsonForCompilers` proposal. Should generate `Makefile`    | Yes          |
|`esy any command here`   | Executes `any command here` but in the sandbox that would be printed via `esy`                        | No          |


#### Test

Run the test. The output shows the environment computed for a single package
`PackageA`.  Some errors are logged into the comments of the output.

```
cd tests/TestOne/PackageA
./test.sh
```

The output isn't actually verified yet. We should create many more similar
tests, even if they don't work correctly yet.

#### Next

- Populate all of the variables in `pjc` proposal.
- Should generate a build for all packages in makefile form.
- Implement "scope" concept as described in `esy.js` comments.
- Take `buildTimeOnlyDependencies` in order to "cut off" scope of environment
  variables.
- Automatically set up `_build` and `_install` directories, populate variables
  accordingly.

#### Try it out on a sample project

https://github.com/andreypopp/esy-ocaml-project

#### Origins

This is a fork of [`dependency-env`](https://github.com/reasonml/dependency-env) which is more stable.


#### Developing

When developing `esy` (or cloning the repo to use locally), you must have `filterdiff` installed (which you can obtain via `brew install patchutils`).


To make changes to `esy` and test them locally, check out and build the `esy` repo as such:

    git clone git@github.com:jordwalke/esy.git
    cd esy
    npm install
    git submodule init
    git submodule update
    make  convert-opam-packages

Then you may "point" to that built version of esy by simply referencing its path.

    /path/to/esy/.bin/esy build

#### Supporting More OPAM packages

- Make sure you've ran `git submodule init` and `git submodule update`.
- Add the OPAM package name and versions to
  ./opam-packages-conversion/convertedPackages.txt
- If the package/version was recently added to `OPAM`, you should `cd` into
  `opam-packages-conversion/opam-repository`, `git fetch --all`, and then `git
  checkout origin/master` to make sure you've got the latest OPAM universe that
  you will convert from. `cd` back into the `esy` project root, and then `git
  status` will show git changes for you to commit.
- Make a new commit with all the above changes.
- Push the update to `esy` `master`.
- Clone a *fresh* new clone of `esy` (so that the submodules initialize
  correctly), then publish a new beta release as described next.
  

#### Pushing a Beta Release

On a clean branch off of `origin/master`, run

    # npm install if needed.
    npm install
    git submodule init
    git submodule update
    # Substitute your version number below
    make beta-release VERSION=0.0.2

Then follow the instructions for pushing a tagged release to github.

Once pushed, other people can install that tagged release globally like this:

    npm install -g git://github.com/jordwalke/esy.git#beta-v0.0.2

