[@deriving ord]
type t = {
  path: Path.t,
  mtime: option(float),
};

let ofPath = (path: Path.t) =>
  RunAsync.Syntax.(
    RunAsync.contextf(
      switch%lwt (Lwt_unix.stat(Path.show(path))) {
      | {st_kind: Unix.S_REG, st_mtime, _} =>
        return({path, mtime: Some(st_mtime)})
      | {st_kind: _, _} => error("expected a regular file")
      | exception ([@implicit_arity] Unix.Unix_error(Unix.ENOENT, "stat", _)) =>
        return({path, mtime: None})
      },
      "reading file info for %a",
      Path.pp,
      path,
    )
  );

let ofPathSet = (paths: Path.Set.t) =>
  RunAsync.List.mapAndJoin(
    ~concurrency=100,
    ~f=ofPath,
    Path.Set.elements(paths),
  );
