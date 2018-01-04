/**
 * This module implements utilities which are used to "script" build processes.
 */
type t('a, 'b) = result('a, [> Rresult.R.msg] as 'b);

let ok = Result.ok;

let (/) = Fpath.(/);

let v = Fpath.v;

let withCwd = (path, ~f) => Result.join(Bos.OS.Dir.with_current(path, f, ()));

let exists = Bos.OS.Path.exists;

let mkdir = path =>
  switch (Bos.OS.Dir.create(path)) {
  | Ok(_) => Ok()
  | Error(msg) => Error(msg)
  };

let rmdir = path => Bos.OS.Dir.delete(~recurse=true, path);

let rm = path => Bos.OS.File.delete(path);

let symlink = Bos.OS.Path.symlink;

let symlink_target = Bos.OS.Path.symlink_target;

let symlinkTarget = Bos.OS.Path.symlink_target;

let mv = Bos.OS.Path.move;

let uname = () => {
  let ic = Unix.open_process_in("uname");
  let uname = input_line(ic);
  let () = close_in(ic);
  String.lowercase_ascii(uname);
};

module Let_syntax = Result.Let_syntax;

let rec realpath = (p: Fpath.t) => {
  let%bind p =
    if (Fpath.is_abs(p)) {
      Ok(p);
    } else {
      let%bind cwd = Bos.OS.Dir.current();
      Ok(p |> Fpath.append(cwd) |> Fpath.normalize);
    };
  let _realpath = (p: Fpath.t) => {
    let isSymlinkAndExists = p =>
      switch (Bos.OS.Path.symlink_stat(p)) {
      | Ok({Unix.st_kind: Unix.S_LNK, _}) => Ok(true)
      | _ => Ok(false)
      };
    if (Fpath.is_root(p)) {
      Ok(p);
    } else {
      let%bind isSymlink = isSymlinkAndExists(p);
      if (isSymlink) {
        let%bind target = symlinkTarget(p);
        realpath(target |> Fpath.append(Fpath.parent(p)) |> Fpath.normalize);
      } else {
        let parent = p |> Fpath.parent |> Fpath.rem_empty_seg;
        let%bind parent = realpath(parent);
        Ok(parent / Fpath.basename(p));
      };
    };
  };
  _realpath(p);
};

/**
 * Put temporary file into filesystem with the specified contents and return its
 * filename. This temporary file will be cleaned up at exit.
 */
let putTempFile = (contents: string) => {
  let%bind filename = Bos.OS.File.tmp("%s");
  let%bind () = Bos.OS.File.write(filename, contents);
  Ok(filename);
};

let traverse = (path: Fpath.t, f: (Fpath.t, Unix.stats) => t(_)) : t(_) => {
  let visit = (path: Fpath.t) =>
    fun
    | Ok () => {
        let%bind stats = Bos.OS.Path.symlink_stat(path);
        f(path, stats);
      }
    | error => error;
  Result.join(Bos.OS.Path.fold(~dotfiles=true, visit, Ok(), [path]));
};
