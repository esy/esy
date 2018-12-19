let toRunAsync ?(desc="I/O failed") promise =
  let open RunAsync.Syntax in
  try%lwt
    let%lwt v = promise () in
    return v
  with Unix.Unix_error (err, _, _) ->
    let msg = Unix.error_message err in
    error (Printf.sprintf "%s: %s" desc msg)

let readFile (path : Path.t) =
  let path = Path.show path in
  let desc = Printf.sprintf "Unable to read file %s" path in
  toRunAsync ~desc (fun () ->
    let f ic = Lwt_io.read ic in
    Lwt_io.with_file ~mode:Lwt_io.Input path f
  )

let writeFile ?perm ~data (path : Path.t) =
  let path = Path.show path in
  let desc = Printf.sprintf "Unable to write file %s" path in
  toRunAsync ~desc (fun () ->
    let f oc = Lwt_io.write oc data in
    Lwt_io.with_file ?perm ~mode:Lwt_io.Output path f
  )

let openFile ~mode ~perm path =
  toRunAsync (fun () ->
    Lwt_unix.openfile (Path.show path) mode perm)

let readJsonFile (path : Path.t) =
  let open RunAsync.Syntax in
  let%bind data = readFile path in
  try return (Yojson.Safe.from_string data)
  with Yojson.Json_error msg ->
    errorf "error reading JSON file: %a@\n%s" Path.pp path msg

let writeJsonFile ~json path =
  let data = Yojson.Safe.pretty_to_string json in
  writeFile ~data path

let exists (path : Path.t) =
  let path = Path.show path in
  let%lwt exists = Lwt_unix.file_exists path in
  RunAsync.return exists

let chmod permission (path : Path.t) =
  RunAsync.contextf (
    try%lwt
      let path = Path.show path in
      let%lwt () = Lwt_unix.chmod path permission in
      RunAsync.return ()
    with Unix.Unix_error (errno, _, _) ->
      let msg = Unix.error_message errno in
      RunAsync.error msg
  ) "changing permissions for path %a" Path.pp path

let createDir (path : Path.t) =
  let rec create path =
    try%lwt (
      let path = Path.show path in
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
  let path = Path.show path in
  match%lwt Lwt_unix.stat path with
  | stats -> RunAsync.return stats
  | exception Unix.Unix_error (Unix.ENOTDIR, "stat", _) ->
    RunAsync.error "unable to stat"
  | exception Unix.Unix_error (Unix.ENOENT, "stat", _) ->
    RunAsync.error "unable to stat"

let lstat (path : Path.t) =
  let path = Path.show path in
  try%lwt
    let%lwt stats = Lwt_unix.lstat path in
    RunAsync.return stats
  with
  | Unix.Unix_error (error, _, _) ->
    RunAsync.error (Unix.error_message error)

let isDir (path : Path.t) =
  match%lwt stat path with
  | Ok { st_kind = Unix.S_DIR; _ } -> RunAsync.return true
  | Ok { st_kind = _; _ } -> RunAsync.return false
  | Error _ -> RunAsync.return false

let unlink (path : Path.t) =
  let path = Path.show path in
  let%lwt () = Lwt_unix.unlink path in
  RunAsync.return ()

let rename ~src target =
  let src = Path.show src in
  let target = Path.show target in
  try%lwt
    let%lwt () = Lwt_unix.rename src target in
    RunAsync.return ()
  with
    | Unix.Unix_error (Unix.ENOENT, "rename", filename) ->
      RunAsync.errorf "no such file: %s" filename

let no _path = false

let fold
  ?(skipTraverse=no)
  ~(f : 'a -> Path.t -> Unix.stats -> 'a RunAsync.t)
  ~(init : 'a)
  (path : Path.t) =
  let open RunAsync.Syntax in
  let rec visitPathItems acc path dir =
    match%lwt Lwt_unix.readdir dir with
    | exception End_of_file -> return acc
    | "." | ".." -> visitPathItems acc path dir
    | name ->
      let%lwt acc = visitPath acc Path.(path / name) in
      begin match acc with
      | Ok acc -> visitPathItems acc path dir
      | Error _ -> Lwt.return acc
      end
  and visitPath (acc : 'a) path =
    if skipTraverse path
    then return acc
    else (
      let spath = Path.show path in
      let%lwt stat = Lwt_unix.lstat spath in
      match stat.Unix.st_kind with
      | Unix.S_DIR ->
        let%lwt dir = Lwt_unix.opendir spath in
        Lwt.finalize
          (fun () -> visitPathItems acc path dir)
          (fun () -> Lwt_unix.closedir dir)
      | _ -> f acc path stat
    )
  in
  visitPath init path

let listDir path =
  match%lwt Lwt_unix.opendir (Path.show path) with
  | exception Unix.Unix_error (Unix.ENOENT, "opendir", _) ->
    RunAsync.error "cannot read the directory"
  | exception Unix.Unix_error (Unix.ENOTDIR, "opendir", _) ->
    RunAsync.error "not a directory"
  | dir ->
    let rec readdir names () =
      match%lwt Lwt_unix.readdir dir with
      | exception End_of_file -> RunAsync.return names
      | "." | ".." -> readdir names ()
      | name -> readdir (name::names) ()
    in
    Lwt.finalize (readdir []) (fun () -> Lwt_unix.closedir dir)

let traverse ?skipTraverse ~f path =
  let f _ path stat = f path stat in
  fold ?skipTraverse ~f ~init:() path

let copyStatLwt ~stat path =
  match System.Platform.host with
  | Windows -> Lwt.return () (* copying these stats is not necessary on Windows, and can cause Permission Denied errors *)
  | _ ->
    let path = Path.show path in
    let%lwt () = Lwt_unix.utimes path stat.Unix.st_atime stat.Unix.st_mtime in
    let%lwt () = Lwt_unix.chmod path stat.Unix.st_perm in
    let%lwt () = 
      try%lwt Lwt_unix.chown path stat.Unix.st_uid stat.Unix.st_gid 
      with Unix.Unix_error (Unix.EPERM, _, _) -> Lwt.return ()
    in Lwt.return ()

let copyFileLwt ~src ~dst =

  let origPathS = Path.show src in
  let destPathS = Path.show dst in

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

  let%lwt () = copyStatLwt ~stat dst in
  Lwt.return ()

let copyFile ~src ~dst =
  try%lwt (
    let%lwt () = copyFileLwt ~src ~dst in
    let%lwt stat = Lwt_unix.stat (Path.show src) in
    let%lwt () = copyStatLwt ~stat dst in
    RunAsync.return ()
  ) with Unix.Unix_error (error, _, _) ->
    RunAsync.error (Unix.error_message error)

let rec copyPathLwt ~src ~dst =
  let origPathS = Path.show src in
  let destPathS = Path.show dst in
  let%lwt stat = Lwt_unix.lstat origPathS in
  match stat.st_kind with
  | S_REG ->
    let%lwt () = copyFileLwt ~src ~dst in
    let%lwt () = copyStatLwt ~stat dst in
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
        let%lwt () = copyPathLwt ~src:Path.(src / name) ~dst:Path.(dst / name) in
        traverseDir dir
    in

    let%lwt dir = Lwt_unix.opendir origPathS in
    let%lwt () = Lwt.finalize
      (fun () -> traverseDir dir)
      (fun () -> Lwt_unix.closedir dir)
    in

    let%lwt () = copyStatLwt ~stat dst in

    Lwt.return ()
  | _ ->
    (* XXX: Skips special files: should be an error instead? *)
    Lwt.return ()

let copyPath ~src ~dst =
  let open RunAsync.Syntax in
  let%bind () = createDir (Path.parent dst) in
  try%lwt (
    let%lwt () = copyPathLwt ~src ~dst in
    RunAsync.return ()
  ) with Unix.Unix_error (error, _, _) ->
    RunAsync.error (Unix.error_message error)

let rec rmPathLwt path =
  let pathS = Path.show path in
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
  | S_LNK ->
    Lwt_unix.unlink pathS
  | _ ->
    let%lwt () = Lwt_unix.chmod pathS 0o640 in
    Lwt_unix.unlink pathS

let rmPath path =
  try%lwt (
    let%lwt () = rmPathLwt path in
    RunAsync.return ()
  ) with
    | Unix.Unix_error (Unix.ENOENT, _, _) ->
      RunAsync.return ()
    | Unix.Unix_error (error, _, _) ->
      RunAsync.error (Unix.error_message error)

let randGen = lazy (Random.State.make_self_init ())

let randPath dir pat =
  let rand = Random.State.bits (Lazy.force randGen) land 0xFFFFFF in
  Fpath.(dir / Astring.strf pat (Astring.strf "%06x" rand))

let withTempDir ?tempPath f =
  let open RunAsync.Syntax in
  let tempPath = match tempPath with
    | Some tempPath -> tempPath
    | None -> Path.v (Filename.get_temp_dir_name ())
  in
  let path = randPath tempPath "esy-%s" in
  let%bind () = createDir path in
  Lwt.finalize
    (fun () -> f path)
    (fun () ->
      (* never fail on removing a temp folder. *)
      match%lwt rmPath path with
      | Ok () -> Lwt.return ()
      | Error _ -> Lwt.return ()
    )

let withTempFile ~data f =
  let path = Filename.temp_file "esy" "tmp" in

  let%lwt () =
    let writeContent oc =
      let%lwt () = Lwt_io.write oc data in
      let%lwt () = Lwt_io.flush oc in
      Lwt.return ()
    in
    Lwt_io.with_file ~mode:Lwt_io.Output path writeContent
  in

  Lwt.finalize
    (fun () -> f (Path.v path))
    (fun () ->
      (* never fail on removing a temp file. *)
      try%lwt Lwt_unix.unlink path
      with Unix.Unix_error _ -> Lwt.return ())

let readlink (path : Path.t) =
  let open RunAsync.Syntax in
  let path = Path.show path in
  try%lwt
    let%lwt link = Lwt_unix.readlink path in
    return (Path.v link)
  with Unix.Unix_error (err, _, _) ->
    errorf "readlink %s: %s" path (Unix.error_message err)

let readlinkOpt (path : Path.t) =
  let open RunAsync.Syntax in
  let path = Path.show path in
  try%lwt
    let%lwt link = Lwt_unix.readlink path
    in return (Some (Path.v link))
  with
    | Unix.Unix_error (ENOENT, _, _) -> return None
    | Unix.Unix_error (err, _, _) ->
      errorf "readlink %s: %s" path (Unix.error_message err)

let symlink ?(force=false) ~src dst =
  let open RunAsync.Syntax in

  let symlink' src dst =
    let src = Path.show src in
    let dst = Path.show dst in
    try%lwt
      let%lwt () = Lwt_unix.symlink src dst in
      Lwt.return (Ok ())
    with Unix.Unix_error (err, _, _) ->
      Lwt.return (Error err)
  in

  let mkError err =
    errorf "symlink %a -> %a: %s" Path.pp src Path.pp dst (Unix.error_message err)
  in

  match%lwt symlink' src dst with
  | Ok () -> return ()
  | Error Unix.EEXIST when force ->
    (* try rm path but ignore errors *)
    let%lwt _: unit Run.t = rmPath dst in
    begin match%lwt symlink' src dst with
    | Ok () -> return ()
    | Error err -> mkError err
    end
  | Error err -> mkError err

let realpath path =
  let open RunAsync.Syntax in
  let path =
    if Fpath.is_abs path
    then path
    else
      let cwd = Path.v (Sys.getcwd ()) in
      path |> Fpath.append cwd  |> Fpath.normalize
  in
  let isSymlinkAndExists path =
    match%lwt lstat path with
    | Ok {Unix.st_kind = Unix.S_LNK; _} -> return true
    | _ -> return false
  in
  let rec aux path =
    if Fpath.is_root path
    then return path
    else
      let%bind isSymlink = isSymlinkAndExists path in
      if isSymlink
      then
        let%bind target = readlink path in
        aux (target |> Fpath.append(Fpath.parent(path)) |> Fpath.normalize)
      else
        let parentPath = path |> Fpath.parent |> Fpath.rem_empty_seg in
        let%bind parentPath = aux parentPath  in
        return Path.(parentPath / Fpath.basename path)
  in
  aux (Path.normalize path)
