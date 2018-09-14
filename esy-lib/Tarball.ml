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
    let nf = Path.toString filename in
    let _normalizedOut = Path.toString out in

    let max_ocaml_int = Int64.of_int max_int in

    let readFile input_channel (header : Tar_cstruct.Header.t) =
      let file_size = header.file_size in
      (* If this were to happen we'd have some pretty big problems... *)
      assert (file_size <= max_ocaml_int) ;
      let buf = Cstruct.create (Int64.to_int file_size) in
      Tar_cstruct.really_read input_channel buf ;

      let nameLength = String.length header.file_name in
      let maxLength = nameLength - 2 in

      let filename = Filename.concat (Path.toString out) (String.sub header.file_name 2 maxLength) in

      if filename = "" then
        RunAsync.return ()
      else 
        let filepath = match Path.ofString filename with
        | Ok path -> path
        | Error `Msg message -> failwith message
        in
        let%bind () = match Cstruct.to_string buf with
        | "" -> Fs.createDir filepath
        | data -> Fs.writeFile ~data filepath
        in
        RunAsync.return ()
    in

    let rec readFiles ic =
      match Tar_cstruct.Archive.with_next_file ic readFile with
      | exception Tar_cstruct.Header.End_of_stream -> ()
      | _file -> readFiles ic
    in

    try
      let ic = open_in_bin nf in
      let length = in_channel_length ic in
      let rawTarGz = really_input_string ic length in

      let rawTarFile = match Ezgzip.decompress rawTarGz with
      | (Ok tar) -> tar
      | (Error _) -> (failwith "Invalid gzip")
      in

      let tarFile = Tar_cstruct.make_in_channel (Cstruct.of_string rawTarFile) in

      RunAsync.return (readFiles tarFile)
    with Sys_error message -> RunAsync.error message
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

let unpack ?stripComponents ~dst filename =
  let ext = Path.getExt filename in
  begin match ext with
  | ".zip" -> unpackWithUnzip ?stripComponents ~dst filename
  | _ -> unpackWithTar ?stripComponents ~dst filename
  end

let create ~filename src =
  RunAsync.ofBosError (
    let open Result.Syntax in
    let%bind nf = EsyBash.normalizePathForCygwin (Path.show filename) in
    let%bind ns = EsyBash.normalizePathForCygwin (Path.show src) in
    let cmd = Cmd.(v "tar" % "czf" % nf % "-C" % ns % ".") in
    let%bind res = EsyBash.run (Cmd.toBosCmd cmd) in
    return res
  )
