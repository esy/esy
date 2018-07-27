module Result = EsyLib.Result;
module Path = EsyLib.Path;

type err('b) =
  [> | `Msg(string) | `CommandError(Cmd.t, Bos.OS.Cmd.status)] as 'b;

type t('v, 'e) = result('v, err('e));

let coerceFromMsgOnly = x => (x: result(_, [ | `Msg(string)]) :> t(_, _));
let coerceFromClosed = x => (
  x: result(_, [ | `Msg(string) | `CommandError(Cmd.t, Bos.OS.Cmd.status)]) :>
    t(_, _)
);

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

let rm = path => Bos.OS.Path.delete(~must_exist=false, ~recurse=true, path);
let stat = Bos.OS.Path.stat;
let lstat = Bos.OS.Path.symlink_stat;
let link = Bos.OS.Path.link;
let symlink = Bos.OS.Path.symlink;
let readlink = Bos.OS.Path.symlink_target;

let write = (~perm=?, ~data, path) =>
  Bos.OS.File.write(~mode=?perm, path, data);
let read = path => Bos.OS.File.read(path);

let mv = Bos.OS.Path.move;

let bind = Result.Syntax.Let_syntax.bind;
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
  let traverse = {
    let ignoreSet =
      List.fold_left(
        (set, p) => Path.Set.add(Path.(from / p), set),
        Path.Set.empty,
        ignore,
      );
    `Sat(path => Ok(! Path.Set.mem(path, ignoreSet)));
  };

  let excludePathsWithinSymlink = ref(Path.Set.empty);

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
      } else if (Path.Set.mem(
                   Path.rem_empty_seg(Path.parent(path)),
                   excludePathsWithinSymlink^,
                 )) {
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
          excludePathsWithinSymlink :=
            Path.Set.add(
              Path.rem_empty_seg(path),
              excludePathsWithinSymlink^,
            );
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
