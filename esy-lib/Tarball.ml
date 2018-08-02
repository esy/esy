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
      Logs_lwt.err (fun m -> m
        "@[<v>command failed: %a@\nstderr:@[<v 2>@\n%a@]@\nstdout:@[<v 2>@\n%a@]@]"
        Cmd.pp cmd Fmt.lines stderr Fmt.lines stdout
      );%lwt
      RunAsync.error "error running command"
  in
  try%lwt
    let cmd = Cmd.getToolAndLine cmd in
    Lwt_process.with_process_full cmd f
  with
  | Unix.Unix_error (err, _, _) ->
    let msg = Unix.error_message err in
    RunAsync.error msg
  | _ ->
    RunAsync.error "error running subprocess"

let unpackWithTar ?stripComponents ~dst filename =
  let open RunAsync.Syntax in
  let unpack out = run Cmd.(v "tar" % "xf" % p filename % "-C" % p out) in
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

let unpack ?stripComponents ~dst filename =
  match Path.get_ext filename with
  | ".zip" -> unpackWithUnzip ?stripComponents ~dst filename
  | _ -> unpackWithTar ?stripComponents ~dst filename

let create ~filename src =
  let nf = EsyBash.normalizePathForCygwin (Path.to_string filename) in
  let ns = EsyBash.normalizePathForCygwin (Path.to_string src) in

  match (nf, ns) with 
  | Ok vnf, Ok vns -> 
      let cmd = Cmd.(v "tar" % "czf" % vnf % "-C" % vns % ".") in
      let res = EsyBash.run (Cmd.toBosCmd cmd) in
      begin match res with
      | _ -> RunAsync.return ()
      end
  | _ -> RunAsync.error ("Unable to tar") 

