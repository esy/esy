type t = {
  root : Path.t;
  name : Path.t;
}

let pp fmt file =
  Fmt.pf fmt "%a/%a" Path.pp file.root Path.pp file.name

let digest file =
  let path = Path.(file.root // file.name) in
  Digestv.ofFile path

let ofDir base =
  let rec loop sub =
    let open RunAsync.Syntax in
    let root = Path.(base // sub) in
    if%bind Fs.exists root
    then
      let%bind files = Fs.listDir root in
      let f name =
        if%bind Fs.isDir Path.(root / name)
        then
          loop Path.(sub / name)
        else
          return [{name=Path.(sub / name); root=base;}]
      in
      let%bind lists = RunAsync.List.mapAndJoin ~concurrency:20 ~f files in
      return (List.concat lists)
    else
      return []
  in
  loop (Path.v ".")

let placeAt path file =
  let open RunAsync.Syntax in
  let src = Path.(file.root // file.name) in
  let dst = Path.(path // file.name) in
  let () = Logs.debug(fun m -> m "Copying file from %s to %s" (Path.showPretty src) (Path.showPretty dst)) in
  let%bind () = Fs.createDir (Path.parent dst) in
  Fs.copyFile ~src ~dst
  
