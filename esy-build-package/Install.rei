/**

  This implements "esy-installer" command.

  See [1] for documentation.

  [1]: https://opam.ocaml.org/doc/Manual.html#lt-pkgname-gt-install

 */;

/**

  [install ~prefixPath installFilename] executes installation as described in an
  *.install file [installFilename] to [prefixPath] path.

  if [enableLinkingOptimization] is enabled then installer is free to try to use
  symlinks and/or hardlinks instead of copying files (note this will only work
  if installer don't install across different mount points).

  Note that this is designed so it the prefix path doesn't contain any files.

 */

let install:
  (~enableLinkingOptimization: bool, ~prefixPath: Fpath.t, Fpath.t) =>
  Run.t(unit, _);
