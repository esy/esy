module Result = EsyLib.Result;
module Path = EsyLib.Path;

type err('b) =
  [> | `Msg(string) | `CommandError(Cmd.t, Bos.OS.Cmd.status)] as 'b;

type t('v, 'e) = result('v, err('e));

let coerceFrmMsgOnly = x => (x: result(_, [ | `Msg(string)]) :> t(_, _));

let ok = Result.ok;
let return = v => Ok(v);
let error = msg => Error(`Msg(msg));

let v = Fpath.v;
let (/) = Fpath.(/);

let withCwd = (path, ~f) =>
  Result.join(Bos.OS.Dir.with_current(path, f, ()));

let exists = Bos.OS.Path.exists;

let mkdir = path =>
  switch (Bos.OS.Dir.create(path)) {
  | Ok(_) => Ok()
  | Error(msg) => Error(msg)
  };

let ls = path => Bos.OS.Dir.contents(~dotfiles=true, ~rel=true, path);

let rm = path =>
  switch (Bos.OS.Path.stat(path)) {
  | Ok({Unix.st_kind: S_DIR, _}) => Bos.OS.Dir.delete(~recurse=true, path)
  | Ok(_) => Bos.OS.File.delete(path)
  | Error(err) => Error(err)
  };

let lstat = Bos.OS.Path.symlink_stat;
let symlink = Bos.OS.Path.symlink;
let readlink = Bos.OS.Path.symlink_target;

let write = (~data, path) => Bos.OS.File.write(path, data);
let read = path => Bos.OS.File.read(path);

let mv = Bos.OS.Path.move;

module Let_syntax = Result.Syntax.Let_syntax;

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
        let%bind target = readlink(p);
        realpath(
          target |> Fpath.append(Fpath.parent(p)) |> Fpath.normalize,
        );
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
let createTmpFile = (contents: string) => {
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

let copyContents = (~from, ~ignore=[], dest) => {
  let excludePaths =
    List.fold_left(
      (set, p) => Path.Set.add(Path.(from / p), set),
      Path.Set.empty,
      ignore,
    );

  let traverse = `Sat(p => Ok(! Path.Set.mem(p, excludePaths)));

  let rebasePath = path =>
    switch (Fpath.relativize(~root=from, path)) {
    | Some(p) => Path.(dest /\/ p)
    | None => path
    };

  let f = (path, acc) =>
    switch (acc) {
    | Ok () =>
      if (Path.equal(path, from)) {
        Ok();
      } else {
        let%bind stats = Bos.OS.Path.symlink_stat(path);
        let nextPath = rebasePath(path);
        switch (stats.Unix.st_kind) {
        | Unix.S_DIR =>
          let _ = Bos.OS.Dir.create(nextPath);
          Ok();
        | Unix.S_REG =>
          let%bind data = Bos.OS.File.read(path);
          let%bind () = Bos.OS.File.write(nextPath, data);
          Bos.OS.Path.Mode.set(nextPath, stats.Unix.st_perm);
        | Unix.S_LNK =>
          let%bind targetPath = Bos.OS.Path.symlink_target(path);
          let nextTargetPath = rebasePath(targetPath);
          Bos.OS.Path.symlink(~target=nextTargetPath, nextPath);
        | _ => /* ignore everything else */ Ok()
        };
      }
    | Error(err) => Error(err)
    };

  EsyLib.Result.join(
    Bos.OS.Path.fold(~dotfiles=true, ~traverse, f, Ok(), [from]),
  );
};
