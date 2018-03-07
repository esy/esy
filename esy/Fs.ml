let toRunAsync ?(desc="I/O failed") promise =
  let open RunAsync.Syntax in
  try%lwt
    let%lwt v = promise () in
    return v
  with Unix.Unix_error (err, _, _) ->
    let msg = Unix.error_message err in
    error (Printf.sprintf "%s: %s" desc msg)

let readFile (path : Path.t) =
  let path = Path.to_string path in
  let desc = Printf.sprintf "Unable to read file %s" path in
  toRunAsync ~desc (fun () ->
    let f ic = Lwt_io.read ic in
    Lwt_io.with_file ~mode:Lwt_io.Input path f
  )

let openFile ~mode ~perm path =
  toRunAsync (fun () ->
    Lwt_unix.openfile (Path.to_string path) mode perm)

let readJsonFile (path : Path.t) =
  let open RunAsync.Syntax in
  let%bind data = readFile path in
  return (Yojson.Safe.from_string data)

let exists (path : Path.t) =
  let path = Path.to_string path in
  let%lwt exists = Lwt_unix.file_exists path in
  RunAsync.return exists

let chmod permission (path : Path.t) =
  let path = Path.to_string path in
  let%lwt () = Lwt_unix.chmod path permission in
  RunAsync.return ()

let createDirectory (path : Path.t) =
  let rec create path =
    try%lwt (
      let path = Path.to_string path in
      Lwt_unix.mkdir path 0o777
    ) with
    | Unix.Unix_error (Unix.EEXIST, _, _) ->
      Lwt.return ()
    | Unix.Unix_error (Unix.ENOENT, _, _) ->
      let%lwt () = create (Path.parent path) in
      let%lwt () = create path in
      Lwt.return ()
  in
  let%lwt () = create path in
  RunAsync.return ()

let stat (path : Path.t) =
  let path = Path.to_string path in
  let%lwt stats = Lwt_unix.stat path in
  RunAsync.return stats

let unlink (path : Path.t) =
  let path = Path.to_string path in
  let%lwt () = Lwt_unix.unlink path in
  RunAsync.return ()

let no _path = false

let fold ?(skipTraverse=no) ~f ~(init : 'a) (path : Path.t) =
  let rec visitPathItems acc path dir =
    match%lwt Lwt_unix.readdir dir with
    | exception End_of_file -> Lwt.return acc
    | "." | ".." -> visitPathItems acc path dir
    | name ->
      let%lwt acc = visitPath acc Path.(path / name) in
      visitPathItems acc path dir
  and visitPath (acc : 'a) path =
    if skipTraverse path
    then Lwt.return acc
    else (
      let spath = Path.to_string path in
      let%lwt stat = Lwt_unix.stat spath in
      match stat.Unix.st_kind with
      | Unix.S_DIR ->
        let%lwt dir = Lwt_unix.opendir spath in
        Lwt.finalize
          (fun () -> visitPathItems acc path dir)
          (fun () -> Lwt_unix.closedir dir)
      | _ -> f acc path stat
    )
  in
  let%lwt v = visitPath init path
  in RunAsync.return v

let copyStatLwt ~stat path =
  let path = Path.to_string path in
  let%lwt () = Lwt_unix.utimes path stat.Unix.st_atime stat.Unix.st_mtime in
  let%lwt () = Lwt_unix.chmod path stat.Unix.st_perm in
  let%lwt () =
    try%lwt Lwt_unix.chown path stat.Unix.st_uid stat.Unix.st_gid
    with Unix.Unix_error (Unix.EPERM, _, _) -> Lwt.return ()
  in Lwt.return ()

let copyFileLwt ~origPath ~destPath =

  let origPathS = Path.to_string origPath in
  let destPathS = Path.to_string destPath in

  let chunkSize = 1024 * 1024 (* 1mb *) in

  let%lwt stat = Lwt_unix.stat origPathS in

  let copy ic oc =
    let buffer = Bytes.create chunkSize in
    let rec loop () =
      match%lwt Lwt_io.read_into ic buffer 0 chunkSize with
      | 0 -> Lwt.return ()
      | bytesRead ->
        let%lwt () = Lwt_io.write_from_exactly oc buffer 0 bytesRead in
        loop ()
    in loop ()
  in

  let%lwt () =
    Lwt_io.with_file
      origPathS
      ~flags:Lwt_unix.[O_RDONLY]
      ~mode:Lwt_io.Input
      (fun ic ->
        Lwt_io.with_file
          ~mode:Lwt_io.Output
          ~flags:Lwt_unix.[O_WRONLY; O_CREAT; O_TRUNC]
          ~perm:stat.Unix.st_perm
          destPathS
          (copy ic))
  in

  let%lwt () = copyStatLwt ~stat destPath in
  Lwt.return ()

let rec copyPathLwt ~origPath ~destPath =
  let origPathS = Path.to_string origPath in
  let destPathS = Path.to_string destPath in
  let%lwt stat = Lwt_unix.lstat origPathS in
  match stat.st_kind with
  | S_REG ->
    let%lwt () = copyFileLwt ~origPath ~destPath in
    let%lwt () = copyStatLwt ~stat destPath in
    Lwt.return ()
  | S_LNK ->
    let%lwt link = Lwt_unix.readlink origPathS in
    Lwt_unix.symlink link destPathS
  | S_DIR ->
    let%lwt () = Lwt_unix.mkdir destPathS 0o700 in

    let rec traverseDir dir =
      match%lwt Lwt_unix.readdir dir with
      | exception End_of_file -> Lwt.return ()
      | "." | ".." -> traverseDir dir
      | name ->
        let%lwt () = copyPathLwt ~origPath:Path.(origPath / name) ~destPath:Path.(destPath / name) in
        traverseDir dir
    in

    let%lwt dir = Lwt_unix.opendir origPathS in
    let%lwt () = Lwt.finalize
      (fun () -> traverseDir dir)
      (fun () -> Lwt_unix.closedir dir)
    in

    let%lwt () = copyStatLwt ~stat destPath in

    Lwt.return ()
  | _ ->
    (* XXX: Skips special files: should be an error instead? *)
    Lwt.return ()

let rec rmPathLwt path =
  let pathS = Path.to_string path in
  let%lwt stat = Lwt_unix.lstat pathS in
  match stat.st_kind with
  | S_DIR ->
    let rec traverseDir dir =
      match%lwt Lwt_unix.readdir dir with
      | exception End_of_file -> Lwt.return ()
      | "." | ".." -> traverseDir dir
      | name ->
        let%lwt () = rmPathLwt Path.(path / name) in
        traverseDir dir
    in

    let%lwt dir = Lwt_unix.opendir pathS in
    let%lwt () = Lwt.finalize
      (fun () -> traverseDir dir)
      (fun () -> Lwt_unix.closedir dir)
    in

    Lwt_unix.rmdir pathS
  | _ ->
    Lwt_unix.unlink pathS

let copyFile ~origPath ~destPath =
  try%lwt (
    let%lwt () = copyFileLwt ~origPath ~destPath in
    let%lwt stat = Lwt_unix.stat (Path.to_string origPath) in
    let%lwt () = copyStatLwt ~stat destPath in
    RunAsync.return ()
  ) with Unix.Unix_error (error, _, _) ->
    RunAsync.error (Unix.error_message error)

let copyPath ~origPath ~destPath =
  let open RunAsync.Syntax in
  let%bind () = createDirectory (Path.parent destPath) in
  try%lwt (
    let%lwt () = copyPathLwt ~origPath ~destPath in
    RunAsync.return ()
  ) with Unix.Unix_error (error, _, _) ->
    RunAsync.error (Unix.error_message error)

let rmPath path =
  try%lwt (
    let%lwt () = rmPathLwt path in
    RunAsync.return `Removed
  ) with
    | Unix.Unix_error (Unix.ENOENT, _, _) ->
      RunAsync.return `NoSuchPath
    | Unix.Unix_error (error, _, _) ->
      RunAsync.error (Unix.error_message error)

let withTempDir ?tempDir f =
  let tempDir = match tempDir with
  | Some tempDir -> tempDir
  | None -> Filename.get_temp_dir_name ()
  in
  let path = Path.v (Filename.temp_file ~temp_dir:tempDir "esy" "tmp") in
  Lwt.finalize
    (fun () -> f path)
    (fun () -> rmPathLwt path)

let withTempFile content f =
  let path = Filename.temp_file "esy" "tmp" in

  let%lwt () =
    let writeContent oc =
      let%lwt () = Lwt_io.write oc content in
      let%lwt () = Lwt_io.flush oc in
      Lwt.return ()
    in
    Lwt_io.with_file ~mode:Lwt_io.Output path writeContent
  in

  Lwt.finalize
    (fun () -> f (Path.v path))
    (fun () -> Lwt_unix.unlink path)
