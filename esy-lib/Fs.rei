/**
 * Async filesystem API.
 */;

let readFile: Path.t => RunAsync.t(string);

let writeFile: (~perm: int=?, ~data: string, Path.t) => RunAsync.t(unit);

let readJsonFile: Path.t => RunAsync.t(Yojson.Safe.t);

let writeJsonFile: (~json: Yojson.Safe.t, Path.t) => RunAsync.t(unit);

let openFile:
  (~mode: list(Lwt_unix.open_flag), ~perm: int, Path.t) =>
  RunAsync.t(Lwt_unix.file_descr);

/** Check if the path exists */
let exists: Path.t => RunAsync.t(bool);

/** Check if the path exists and is a directory */
let isDir: Path.t => RunAsync.t(bool);
let isDirSync: Path.t => bool;

let unlink: Path.t => RunAsync.t(unit);

/** readlink */
let readlink: Path.t => RunAsync.t(Path.t);

/** Link readlink but returns [None] if path doesn't not exist. */
let readlinkOpt: Path.t => RunAsync.t(option(Path.t));

let symlink: (~force: bool=?, ~src: Path.t, Path.t) => RunAsync.t(unit);
let rename:
  (~attempts: int=?, ~skipIfExists: bool=?, ~src: Path.t, Path.t) =>
  RunAsync.t(unit);

let realpath: Path.t => RunAsync.t(Path.t);

let stat: Path.t => RunAsync.t(Unix.stats);

let lstat: Path.t => RunAsync.t(Unix.stats);

/** List directory and return a list of names excluding . and .. */
let listDir: Path.t => RunAsync.t(list(string));

let createDir: Path.t => RunAsync.t(unit);

let chmod: (int, Path.t) => RunAsync.t(unit);

let fold:
  (
    ~skipTraverse: Path.t => bool=?,
    ~f: ('a, Path.t, Unix.stats) => RunAsync.t('a),
    ~init: 'a,
    Path.t
  ) =>
  RunAsync.t('a);

let traverse:
  (
    ~skipTraverse: Path.t => bool=?,
    ~f: (Path.t, Lwt_unix.stats) => RunAsync.t(unit),
    Path.t
  ) =>
  RunAsync.t(unit);

let copyFile: (~src: Path.t, ~dst: Path.t) => RunAsync.t(unit);
let copyPath: (~src: Path.t, ~dst: Path.t) => RunAsync.t(unit);

let rmPath: Path.t => RunAsync.t(unit);
let rmPathLwt: Path.t => Lwt.t(unit);

let withTempDir:
  (~tempPath: Path.t=?, Path.t => RunAsync.t('a)) => RunAsync.t('a);
let withTempFile: (~data: string, Path.t => Lwt.t('a)) => Lwt.t('a);

let randomPathVariation: Fpath.t => RunAsync.t(Fpath.t);
