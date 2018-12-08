type t = {
  path : Path.t;
  mtime : float option;
} [@@deriving ord]

let ofPath (path : Path.t) =
  let open RunAsync.Syntax in
  RunAsync.contextf (
    match%lwt Lwt_unix.stat (Path.show path) with
    | {st_kind = Unix.S_REG; st_mtime; _} ->
      return {path; mtime = Some st_mtime;}
    | {st_kind = _; _ } ->
      error "expected a regular file"
    | exception Unix.Unix_error (Unix.ENOENT, "stat", _) ->
      return {path; mtime = None;}
    ) "reading file info for %a" Path.pp path

let ofPathSet (paths : Path.Set.t) =
  RunAsync.List.mapAndJoin ~concurrency:100 ~f:ofPath (Path.Set.elements paths)
