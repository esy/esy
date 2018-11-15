type t = {
  name : string;
  root : Path.t;
  checksum : Checksum.t;
}

let checksum file = file.checksum

let ofDir root =
  let open RunAsync.Syntax in
  if%bind Fs.exists root
  then
    let%bind files = Fs.listDir root in
    let f name =
      let%bind checksum = Checksum.computeOfFile ~kind:Checksum.Sha256 Path.(root / name) in
      return {name; root; checksum;}
    in
    RunAsync.List.mapAndJoin ~concurrency:20 ~f files
  else
    return []

let placeAt path file =
  Fs.copyFile
    ~src:Path.(file.root // v file.name)
    ~dst:Path.(path // v file.name)
