let stripComponentFrom ?stripComponents out =
  let open RunAsync.Syntax in
  let rec find path = function
    | 0 -> return path
    | n ->
      begin match%bind Fs.listDir path with
      | [item] -> find Path.(path / item) (n - 1)
      | [] -> error "unpacking: unable to strip path components: empty dir"
      | _ -> error "unpacking: unable to strip path components: multiple root dirs"
      end
  in
  match stripComponents with
  | None -> return out
  | Some n ->
    find out n

let copyAll ~src ~dst () =
  let open RunAsync.Syntax in
  let%bind items = Fs.listDir src in
  let f item = Fs.copyPath ~src:Path.(src / item) ~dst:Path.(dst / item) in
  RunAsync.List.processSeq ~f items

let run cmd =
  let f p =
    let%lwt stdout = Lwt_io.read p#stdout
    and stderr = Lwt_io.read p#stderr in
    match%lwt p#status with
    | Unix.WEXITED 0 ->
      RunAsync.return ()
    | _ ->
      let%lwt () = Logs_lwt.err (fun m -> m
        "@[<v>command failed: %a@\nstderr:@[<v 2>@\n%a@]@\nstdout:@[<v 2>@\n%a@]@]"
        Cmd.pp cmd Fmt.lines stderr Fmt.lines stdout
      ) in
      RunAsync.error "error running command"
  in
  try%lwt
    EsyBashLwt.with_process_full cmd f	
  with
  | Unix.Unix_error (err, _, _) ->
    let msg = Unix.error_message err in
    RunAsync.error msg
  | _ ->
    RunAsync.error "error running subprocess"

let unpackWithTar ?stripComponents ~dst filename =
  let open RunAsync.Syntax in
  let unpack out = 
    let%bind cmd = RunAsync.ofBosError (
      let open Result.Syntax in
      let nf = EsyBash.normalizePathForCygwin (Path.show filename) in
      let normalizedOut = EsyBash.normalizePathForCygwin (Path.show out) in
      return Cmd.(v "tar" % "xf" % nf % "-C" % normalizedOut)
    )
    in
    run cmd
  in
  match stripComponents with
  | Some stripComponents ->
    Fs.withTempDir begin fun out ->
      let%bind () = unpack out in
      let%bind out = stripComponentFrom ~stripComponents out in
      copyAll ~src:out ~dst ()
    end
  | None -> unpack dst

let unpackWithUnzip ?stripComponents ~dst filename =
  let open RunAsync.Syntax in
  let unpack out = run Cmd.(v "unzip" % "-q" % "-d" % p out % p filename) in
  match stripComponents with
  | Some stripComponents ->
    Fs.withTempDir begin fun out ->
      let%bind () = unpack out in
      let%bind out = stripComponentFrom ~stripComponents out in
      copyAll ~src:out ~dst ()
    end
  | None -> unpack dst

let zipHeader =
  (*
   * From https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT
   *
   *   0x50 0x4b 0x03 0x04
   *
   *)
  Int32.of_string "67324752"

let checkIfZip filename =
  let checkZipHeader ic =
    let%lwt v = Lwt_io.read_int32 ic in
    Lwt.return (Int32.compare v zipHeader = 0)
  in
  try%lwt
    let buffer = Lwt_bytes.create 16 in
    Lwt_io.(with_file ~buffer ~mode:Input (Path.show filename) checkZipHeader)
  with _ -> Lwt.return false

let unpack ?stripComponents ~dst filename =
  match Path.getExt ~multi:true filename with
  | ".gz"
  | ".tar"
  | ".tar.gz"
  | ".tar.bz2" -> unpackWithTar ?stripComponents ~dst filename
  | ".zip" -> unpackWithUnzip ?stripComponents ~dst filename
  | _ ->
    if%lwt checkIfZip filename
    then unpackWithUnzip ?stripComponents ~dst filename
    else unpackWithTar ?stripComponents ~dst filename

let create ~filename ?outpath:(outpath=".") src =
  RunAsync.ofBosError (
    let open Result.Syntax in
    let nf = EsyBash.normalizePathForCygwin (Path.show filename) in
    let ns = EsyBash.normalizePathForCygwin (Path.show src) in
    let cmd = Cmd.(v "tar" % "czf" % nf % "-C" % ns % outpath) in
    let%bind res = EsyBash.run (Cmd.toBosCmd cmd) in
    return res
  )
