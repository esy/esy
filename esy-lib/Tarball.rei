/**
 * Operate on tarballs on filesystem
 *
 * The implementaton uses tar command.
 */;

/**
 * Unpack [filename] into [dst].
 */

let unpack:
  (~stripComponents: int=?, ~dst: Path.t, Path.t) => RunAsync.t(unit);

/**
 * Create tarball [filename] by archiving [src] path.
 */

let create:
  (~filename: Path.t, ~outpath: string=?, Path.t) => RunAsync.t(unit);

let checkIfZip: Path.t => Lwt.t(bool);
