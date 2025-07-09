---
id: github-actions
title: "Github Actions"
---

This action will setup [`esy`](https://esy.sh/) and cache any dependencies that
are built (hopefully saving you CI minutes). Additionally, still in
alpha phase, it can help you package your apps for multiple platforms
into a single NPM tarball.

For instance,

```
npm i -g your-app
```

Even if it's single command, the tarball can contain binaries for multiple
target platforms - this action can help you prepare individual
platform binaries, and later bundle them all together with a
postinstall script that will install the correct binaries.

Another benefit of this approach, is that, this action creates binary wrappers
that make your apps self-sufficient in terms of runtime dependencies. For
instance, if you need a runtime dependency (say, `zlib`), it can be tricky to
make sure the user has the correct version installed via their system package
manager. On Windows this is harder that one might expect. Read more about binary
wrappers on [`esy` documentation](https://esy.sh/docs/concepts/#release)

## Example

```yml
name: Build

on: [push]

jobs:
  build:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, macos-13, windows-latest]
    steps:
      - uses: actions/checkout@v4
      - uses: esy/github-action@v2
        with:
          cache-key: ${{ hashFiles('esy.lock/index.json') }}

```

## How does it work?

To create cross-platform builds without this action, you'll need to

1. Run `esy npm-release` on each `${{ matrix.os }}`
2. Upload the `_release` folder as an artifact for a later job.
3. In a job later, download the `_release` folder from each platform and place
   them together inside that NPM package that would be distributed. Now, the NPM
   package would contain binaries for multiple platforms.
4. Make sure there's a postinstall script that would install the correct target
   platform's binaries (by inspect the environment)
5. Run `esyInstallRelease.js` to set up the binary wrappers.

With this action, you wont need to do any of these. It will do all this for you
and upload a `npm-release.tgz` for you to distribute later.

## Static linking

Statically linked binaries are desirable for many reasons. To build such binaries for
OCaml projects, you'll need `musl-libc` and the most portable way of gettting it
is Docker.

This action doesn't provide a convenient way to produce statically linked
binaries yet. You'll have to set up a separate job that uses Docker Actions,
build the OCaml project with a `musl` enabled OCaml compiler inside a docker
container and copy the artifacts out.

Here's an example `Dockerfile` to create such a container.

```dockerfile
FROM esydev/esy:nightly-alpine-latest

COPY package.json package.json
COPY esy.lock esy.lock
RUN esy i
RUN esy build-dependencies
COPY hello.ml hello.ml
RUN esy

ENTRYPOINT ["/entrypoint.sh"]
```

Here's an example job on Github.

```yaml
static-build:
  runs-on: ubuntu-latest
  steps:
    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3
    - name: Build and push
      uses: docker/build-push-action@v5
      with:
        file: ./docker/DevImage.Dockerfile
        push: false
        tags: user/app:latest
    - run: |
        docker container run --pull=never -itd --network=host --name "<CONTAINER_NAME>" "<IMAGE:TAG>"
        docker cp "<CONTAINER_NAME>:/usr/local/lib/esy" "<HOST_PATH>/lib/esy"
        docker cp "<CONTAINER_NAME>:/usr/local/bin/esy" "<HOST__PATH>/bin"
        docker cp "<CONTAINER_NAME>:/usr/local/bin/esyInstallRelease.js" "<HOST_PATH>/bin"
      name: "Copy artifacts from /usr/local/ in the container"
    - run: |
        tar czf npm-tarball.tgz _container_release
        mv npm-tarball.tgz _container_release
```

For a complete working example, refer
[how esy does this](https://github.com/esy/esy/blob/e124b61db298c9f917478c013d8ee700ce67a5ff/.github/workflows/release.yml#L42).

## Inputs

### Required inputs

#### `cache-key`

The cache key. Typically `${{ hashFiles('esy.lock/index.json') }}`. You could
also use a prefix additionally to bust cache when needed.

Example: `20240801-2-${{ hashFiles('esy.lock/index.json') }}`

#### `source-cache-key`

Typically a value similar to `cache-key` but used instead for caching the
sources of the dependencies.

### Optional inputs

The following inputs are optional. When missing, the actions will fallback to
use defaults are mentioned below.

#### `esy-prefix`

Path where esy can setup the cache. Default: `$HOME/.esy`

#### `working-directory`

Working directory of the project. Useful for projects that place esy project
under a folder. It's converted into an absolute path, if it already isn't.

Default: Action workspace root.

#### `manifest`

JSON or opam file to be used. Useful only if you use [multiple
sandboxes](/docs/multiple-sandboxes) feature. 

Example: if the manifest file of
the secondary sandbox is `foo.json`, the value for this field becomes `foo`.

#### `prepare-npm-artifacts-mode`

Runs a step that prepare artifacts for releasing the app to NPM. Useful for CLI
apps. These artifacts are later used by, `bundle-npm-tarball-mode`.


#### `bundle-npm-artifacts-mode`

Runs a steps that bundle artifacts so that a single NPM tarball that contains
binaries built for different platforms. This way, the app can be distributed on
NPM under a single command, but will work on multiple platforms. `esy` itself
uses this mode.

#### `postinstall-js`

Path to a custom `postinstall.js` file that could be placed in the final bundled
NPM tarball.

#### `setup-esy`

Flag to control if esy itself should be installed by the action By default, it's
true. You can disable it if you wish to install esy yourself

Example:

```
    steps:
	  - run: npm i -g esy
	  - uses: esy/github-action@v2
        with:
          source-cache-key: ${{ hashFiles('esy.lock/index.json') }}
          cache-key: ${{ hashFiles('esy.lock/index.json') }}
		  setup-esy: false

```

#### `setup-esy-tarball`

URL to esy tarball. Must be provided together with shasum and version. Else, the
action will default to latest from NPM  
Example: `https://registry.npmjs.org/esy/-/esy-0.7.2.tgz`

#### `setup-esy-shasum`

shasum of the tarball. Must be provided together with shasum and version. Else,
the action will default to latest from NPM

#### `setup-esy-version`

version of the esy tool. Must be provided together with shasum and version.
Else, the action will default to latest from NPM

#### `setup-esy-npm-package`

Alternative NPM package that contains esy. Example: `@diningphilosophers/esy`.

## Example project

You can find an example toy project [here](https://github.com/esy/example-github-actions).

## License

BSD 2-Clause License
