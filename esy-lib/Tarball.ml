let unpackWithTar ?stripComponents ~dst filename =
  let cmd =
    let cmd = Cmd.(v "tar" % "xf" % p filename) in
    let cmd =
      match stripComponents with
      | Some stripComponents ->
        Cmd.(cmd % "--strip-components" % string_of_int(stripComponents))
      | None -> cmd
    in
    let cmd = Cmd.(cmd % "-C" % p dst) in
    cmd
  in
  ChildProcess.run cmd

let unpackWithUnzip ?stripComponents ~dst filename =
  let open RunAsync.Syntax in
  Fs.withTempDir begin fun out ->
    let cmd = Cmd.(v "unzip" % "-q" % "-d" % p out % p filename) in
    let%bind () = ChildProcess.run cmd in
    let%bind out =
      match stripComponents with
      | None -> return out
      | Some n ->
        let rec find path = function
          | 0 -> return path
          | n ->
            begin match%bind Fs.listDir path with
            | [item] -> find Path.(path / item) (n - 1)
            | [] -> error "unpackWithUnzip: unable to strip path components"
            | _ -> error "unpackWithUnzip: unable to strip path components"
            end
        in
        find out n
    in
    let%bind items = Fs.listDir out in
    let%bind () =
      let f item = Fs.copyPath ~src:Path.(out / item) ~dst:Path.(dst / item) in
      items |> List.map ~f |> RunAsync.List.waitAll
    in
    return ()
  end

let unpack ?stripComponents ~dst filename =
  match Path.get_ext filename with
  | ".zip" -> unpackWithUnzip ?stripComponents ~dst filename
  | _ -> unpackWithTar ?stripComponents ~dst filename

let create ~filename src =
  let cmd = Cmd.(v "tar" % "czf" % p filename % "-C" % p src % ".") in
  ChildProcess.run cmd
