# esy-core

## Development

Make sure you have esy installed (yes — you need esy to develop esy):

```
% npm install -g esy
```

Then:

```
% make bootstrap
```

Run your editor inside esy environment (`esy vim` for Vim users) and don't
forget to rebuild the code after each change with `make build-dev`.

You can test instantly via `../bin/esy` entry point which automatically uses
freshly compiled artifacts.

Points of interest:

* `esy` — source code for `esy` command
* `esy/bin/esyCommand.ml` — entry point for `esy` command
* `esy-build-package` — source code for `esy-build-package` program
* `esy-build-package/bin/esyBuildPackageCommand.re` — entry point for
  `esy-build-package` program
* `test` — tests
