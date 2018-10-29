[@@@ocaml.warning "-32"]
type t = {
  name : string;
  content : string;
  (* file, permissions add 0o644 default for backward compat. *)
  perm : (int [@default 0o644]);
} [@@deriving yojson, show, ord]

let readOfPath ~prefixPath ~filePath =
  let open RunAsync.Syntax in
  let p = Path.append prefixPath filePath in
  let%bind content = Fs.readFile p
  and stat = Fs.stat p in
  let content = System.Environment.normalizeNewLines content in
  let perm = stat.Unix.st_perm in
  let name = Path.showNormalized filePath in
  return {name; content; perm}

let writeToDir ~destinationDir file =
  let open RunAsync.Syntax in
  let {name; content; perm} = file in
  let dest = Path.append destinationDir (Fpath.v name) in
  let dirname = Path.parent dest in
  let%bind () = Fs.createDir dirname in
  let content =
      if String.get content (String.length content - 1) == '\n'
      then content
      else content ^ "\n"
  in
  let%bind () = Fs.writeFile ~perm:perm ~data:content dest in
  return()
