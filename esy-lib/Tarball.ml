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
    EsyBash.run (Cmd.toBosCmd cmd)

let unpackWithTar ?stripComponents ~dst filename =
  let open RunAsync.Syntax in
  let unpack out =
    RunAsync.ofBosError (
      let open Result.Syntax in
      let%bind nf = EsyBash.normalizePathForCygwin (Path.to_string filename) in
      let%bind normalizedOut = EsyBash.normalizePathForCygwin (Path.to_string out) in
      let%bind ret = run Cmd.(v "tar" % "xf" % nf % "-C" % normalizedOut) in
      return ret
    )
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
  let unpack out =
    RunAsync.ofBosError (
      run Cmd.(v "unzip" % "-q" % "-d" % p out % p filename)
    )
  in
  match stripComponents with
  | Some stripComponents ->
    Fs.withTempDir begin fun out ->
      let%bind () = unpack out in
      let%bind out = stripComponentFrom ~stripComponents out in
      copyAll ~src:out ~dst ()
    end
  | None -> unpack dst

let unpack ?stripComponents ~dst filename =
  let ext = Path.get_ext filename in
  begin match ext with
  | ".zip" -> unpackWithUnzip ?stripComponents ~dst filename
  | _ -> unpackWithTar ?stripComponents ~dst filename
  end

let create ~filename src =
  RunAsync.ofBosError (
    let open Result.Syntax in
    let%bind nf = EsyBash.normalizePathForCygwin (Path.to_string filename) in
    let%bind ns = EsyBash.normalizePathForCygwin (Path.to_string src) in
    let cmd = Cmd.(v "tar" % "czf" % nf % "-C" % ns % ".") in
    let%bind res = EsyBash.run (Cmd.toBosCmd cmd) in
    return res
  )

