type t = {
  name : string;
  root : Path.t;
}

let digest file =
  let path = Path.(file.root / file.name) in
  Digestv.ofFile path

let ofDir root =
  let open RunAsync.Syntax in
  if%bind Fs.exists root
  then
    let%bind files = Fs.listDir root in
    let f name = return {name; root;} in
    RunAsync.List.mapAndJoin ~concurrency:20 ~f files
  else
    return []

let placeAt path file =
  Fs.copyFile
    ~src:Path.(file.root // v file.name)
    ~dst:Path.(path // v file.name)
