type t = {
  name : string;
  root : Path.t;
}

(* let readOfPath ~prefixPath ~filePath = *)
(*   let open RunAsync.Syntax in *)
(*   let p = Path.append prefixPath filePath in *)
(*   let%bind content = Fs.readFile p *)
(*   and stat = Fs.stat p in *)
(*   let content = System.Environment.normalizeNewLines content in *)
(*   let perm = stat.Unix.st_perm in *)
(*   let name = Path.showNormalized filePath in *)
(*   return {name; content; perm} *)

let make root name =
  {root; name;}

let placeAt path file =
  Fs.copyFile
    ~src:Path.(file.root // v file.name)
    ~dst:Path.(path // v file.name)
