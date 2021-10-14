module Result = EsyLib.Result;
module Path = EsyLib.Path;
module System = EsyLib.System;

module Let_syntax = Result.Syntax.Let_syntax;

let ( let* ) = Result.Syntax.( let* );

type err('b) =
  [> | `Msg(string) | `CommandError(Cmd.t, Bos.OS.Cmd.status)] as 'b;

type t('v, 'e) = result('v, err('e));

let coerceFromMsgOnly = x => (x: result(_, [ | `Msg(string)]) :> t(_, _));
let coerceFromClosed = x => (
  x: result(_, [ | `Msg(string) | `CommandError(Cmd.t, Bos.OS.Cmd.status)]) :>
    t(_, _)
);

let ok = Result.Ok();
let return = v => Ok(v);
let error = msg => Error(`Msg(msg));

let errorf = fmt => {
  let kerr = _ => Error(`Msg(Format.flush_str_formatter()));
  Format.kfprintf(kerr, Format.str_formatter, fmt);
};

let runExn = v =>
  switch (v) {
  | Ok(v) => v
  | Error(`Msg(err)) => failwith(err)
  | Error(`CommandError(cmd, _)) =>
    let err = Format.asprintf("error running command %a", Cmd.pp, cmd);
    failwith(err);
  | Error(_) => assert(false)
  };

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

let empty = path =>
  switch%bind (ls(path)) {
  | [] => return(true)
  | _ => return(false)
  };

let rm = path =>
  switch (Bos.OS.Path.symlink_stat(path)) {
  | Ok({Unix.st_kind: S_DIR, _}) =>
    Bos.OS.Path.delete(~must_exist=false, ~recurse=true, path)
  | Ok({Unix.st_kind: S_LNK, _}) =>
    switch (System.Platform.host) {
    | Windows => Bos.OS.Path.delete(~must_exist=false, ~recurse=true, path)
    | _ =>
      switch (Bos.OS.U.unlink(path)) {
      | Ok () => ok
      | Error(`Unix(err)) =>
        let msg = Unix.error_message(err);
        error(msg);
      }
    }
  | Ok({Unix.st_kind: _, _}) => Bos.OS.Path.delete(~must_exist=false, path)
  | Error(_) => ok
  };
let stat = Bos.OS.Path.stat;

let rec statOrError = p =>
  try(Ok(Unix.stat(Fpath.to_string(p)))) {
  | Unix.Unix_error(Unix.EINTR, _, _) => statOrError(p)
  | Unix.Unix_error(errno, call, msg) => Error((errno, call, msg))
  };

let statIfExists = path =>
  switch (statOrError(path)) {
  | Ok(stats) => return(Some(stats))
  | Error((Unix.ENOENT, _call, _msg)) => return(None)
  | Error((errno, _call, _msg)) =>
    errorf("stat %a: %s", Path.pp, path, Unix.error_message(errno))
  };

let lstat = Bos.OS.Path.symlink_stat;

let rec lstatOrError = p =>
  try(Ok(Unix.lstat(Fpath.to_string(p)))) {
  | Unix.Unix_error(Unix.EINTR, _, _) => statOrError(p)
  | Unix.Unix_error(errno, call, msg) => Error((errno, call, msg))
  };

let link = Bos.OS.Path.link;
let symlink = (~force=?, ~target, dest) => {
  let result = Bos.OS.Path.symlink(~force?, ~target, dest);
  /**
     * Windows sometimes reports a failure result even on success.
     * May be related to: https://github.com/dbuenzli/bos/issues/41
     */
  (
    switch (System.Platform.host) {
    | Windows =>
      let errorRegex =
        Str.regexp(".*?The operation completed successfully.*?");
      switch (result) {
      | Ok(_) => result
      | Error(`Msg(msg)) =>
        let r = Str.string_match(errorRegex, msg, 0);
        /* If the error message is "The operation completed successfully", we'll ignore. */
        if (r) {ok} else {result};
      | _ => result
      };
    | _ => result
    }
  );
};
let readlink = Bos.OS.Path.symlink_target;

let write = (~perm=?, ~data, path) =>
  Bos.OS.File.write(~mode=?perm, path, data);

let read = path => Bos.OS.File.read(path);

let copyFile = (~perm=?, srcPath, dstPath) => {
  // Choosen "arbitrarily" but informed by:
  // https://eklitzke.org/efficient-file-copying-on-linux
  let buflen = 1024 * 128;
  let buf = Bytes.create(buflen);
  let rec loop = (ic, oc, ()) => {
    switch (input(ic, buf, 0, buflen)) {
    | 0 => return()
    | n =>
      output(oc, buf, 0, n);
      loop(ic, oc, ());
    };
  };
  let* res =
    Bos.OS.File.with_ic(
      srcPath,
      (ic, ()) =>
        Bos.OS.File.with_oc(~mode=?perm, dstPath, oc => loop(ic, oc), ()),
      (),
    );
  let* res = res;
  res;
};

let mv = Bos.OS.Path.move;

let rec realpath = (p: Fpath.t) => {
  let* p =
    if (Fpath.is_abs(p)) {
      Ok(p);
    } else {
      let* cwd = Bos.OS.Dir.current();
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
      let* isSymlink = isSymlinkAndExists(p);
      if (isSymlink) {
        let* target = readlink(p);
        realpath(
          target |> Fpath.append(Fpath.parent(p)) |> Fpath.normalize,
        );
      } else {
        let parent = p |> Fpath.parent |> Fpath.rem_empty_seg;
        let* parent = realpath(parent);
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
  let* filename = Bos.OS.File.tmp("%s");
  let* () = Bos.OS.File.write(filename, contents);
  Ok(filename);
};

let rec traverse = (root, f) => {
  let* stats = Bos.OS.Path.symlink_stat(root);
  switch (stats.Unix.st_kind) {
  | Unix.S_DIR =>
    let* items = Bos.OS.Dir.contents(root);
    traverseItems(root, items, f);
  | _ => f(root, stats)
  };
}
and traverseItems = (root, items, f) =>
  switch (items) {
  | [] => return()
  | [item, ...items] =>
    let* () = traverse(Fpath.append(root, item), f);
    traverseItems(root, items, f);
  };

let copyContents = (~from, ~ignore=[], dest) => {
  let traverse = {
    let ignoreSet =
      List.fold_left(
        (set, p) => Path.Set.add(Path.(from / p), set),
        Path.Set.empty,
        ignore,
      );
    let visited = ref(Path.Set.empty);
    `Sat(
      path => {
        let stats = Unix.lstat(Fpath.to_string(path));
        visited := Path.Set.add(path, visited^);
        switch (stats.st_kind) {
        | Unix.S_LNK =>
          let linkContents = Unix.readlink(Fpath.to_string(path));
          if (Path.Set.mem(
                Fpath.rem_empty_seg(
                  Fpath.normalize(Path.(path / linkContents)),
                ),
                visited^,
              )) {
            Ok(false);
          } else {
            Ok(true);
          };
        | _ => Ok(!Path.Set.mem(path, ignoreSet))
        };
      },
    );
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
      if (Path.compare(path, from) == 0) {
        Ok();
      } else if (Path.Set.mem(
                   Path.remEmptySeg(Path.parent(path)),
                   excludePathsWithinSymlink^,
                 )) {
        Ok();
      } else {
        // Using Unix.lstat here because for a symlink pointing to a directory
        // Unix.stat gives the st_kind as S_DIR, whereas Unix.lstat gives to correct kind S_LNK
        let stats = Unix.lstat(Fpath.to_string(path));
        let nextPath = rebasePath(path);
        switch (stats.st_kind) {
        | Unix.S_DIR =>
          let _ = Bos.OS.Dir.create(nextPath);
          Ok();
        | Unix.S_REG =>
          let* data = Bos.OS.File.read(path);
          let* {st_atime: atime, st_mtime: mtime, _}: Unix.stats =
            Bos.OS.Path.stat(path);
          let* () = Bos.OS.File.write(nextPath, data);
          Unix.utimes(Fpath.to_string(nextPath), atime, mtime);
          Bos.OS.Path.Mode.set(nextPath, stats.Unix.st_perm);
        | Unix.S_LNK =>
          excludePathsWithinSymlink :=
            Path.Set.add(Path.remEmptySeg(path), excludePathsWithinSymlink^);
          let* targetPath = Bos.OS.Path.symlink_target(path);
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
module Dir = {
  let contents = Bos.OS.Dir.contents;
};
type in_channel = Stdlib.in_channel;
type file_descr = Unix.file_descr;
let withIC = Bos.OS.File.with_ic;
let fileDescriptorOfChannel = Unix.descr_of_in_channel;
let readBytes = Unix.read;

module type T = {
  type in_channel;
  type file_descr;
  let fileDescriptorOfChannel: in_channel => file_descr;
  let read: Fpath.t => t(string, [> | `Msg(string)]);
  let readBytes: (file_descr, Bytes.t, int, int) => int;
  let stat: Fpath.t => t(Unix.stats, [> | `Msg(string)]);
  let withIC:
    (Fpath.t, (in_channel, 'a) => 'b, 'a) => t('b, [> | `Msg(string)]);
  module Dir: {
    let contents:
      (~dotfiles: bool=?, ~rel: bool=?, Fpath.t) =>
      t(list(Fpath.t), [> | `Msg(string)]);
  };
};
