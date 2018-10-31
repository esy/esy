type t = {
  name : string;
  root : Path.t;
}

let make root name =
  {root; name;}

let ofDir root =
  let open RunAsync.Syntax in
  if%bind Fs.exists root
  then
    let%bind files = Fs.listDir root in
    return (List.map ~f:(make root) files)
  else
    return []

let placeAt path file =
  Fs.copyFile
    ~src:Path.(file.root // v file.name)
    ~dst:Path.(path // v file.name)
