type t =
| Md5 of string
| Sha1 of string
| Sha256 of string
| Sha512 of string
[@@deriving eq, ord]

let name (checksum : t) =
  match checksum with
  | Md5 _ -> "md5"
  | Sha1 _ -> "sha1"
  | Sha256 _ -> "sha256"
  | Sha512 _ -> "sha512"

let contents (checksum : t) =
  match checksum with
  | Md5 v
  | Sha1 v
  | Sha256 v
  | Sha512 v -> v

let pp fmt v =
  match v with
  | Md5 v -> Fmt.pf fmt "md5:%s" v
  | Sha1 v -> Fmt.pf fmt "sha1:%s" v
  | Sha256 v -> Fmt.pf fmt "sha256:%s" v
  | Sha512 v -> Fmt.pf fmt "sha512:%s" v

let show v =
  match v with
  | Md5 v -> "md5:" ^ v
  | Sha1 v -> "sha1:" ^ v
  | Sha256 v -> "sha256:" ^ v
  | Sha512 v -> "sha512:" ^ v

let parse v =
  match Astring.String.cut ~sep:":" v with
  | Some ("md5", v) -> Ok (Md5 v)
  | Some ("sha1", v) -> Ok (Sha1 v)
  | Some ("sha256", v) -> Ok (Sha256 v)
  | Some ("sha512", v) -> Ok (Sha512 v)
  | Some (kind, _) -> Error ("unknown checkum kind: " ^ kind)
  | None -> Ok (Sha1 v)

let to_yojson v = `String (show v)
let of_yojson json =
  match json with
  | `String v -> parse v
  | _ -> Error "expected string"

let md5sum =
  match System.host with
  | System.Unix
  | System.Darwin -> Cmd.(v "md5" % "-q")
  | System.Linux
  | System.Cygwin
  | System.Windows
  | System.Unknown -> Cmd.(v "md5sum")
let sha1sum = Cmd.(v "shasum" % "--algorithm" % "1")
let sha256sum = Cmd.(v "shasum" % "--algorithm" % "256")
let sha512sum = Cmd.(v "shasum" % "--algorithm" % "512")

let checkFile ~path (checksum : t) =
  let open RunAsync.Syntax in

  let%bind value =
    let cmd =
      match checksum with
      | Md5 _ -> md5sum
      | Sha1 _ -> sha1sum
      | Sha256 _ -> sha256sum
      | Sha512 _ -> sha512sum
    in
    let%bind out = ChildProcess.runOut Cmd.(cmd % p path) in
    match Astring.String.cut ~sep:" " out with
    | Some (v, _) -> return v
    | None -> return (String.trim out)
  in

  let cvalue = contents checksum in
  if cvalue = value
  then return ()
  else
    let msg =
      Printf.sprintf
        "%s checksum mismatch: expected %s but got %s"
        (name checksum) cvalue value
    in
    error msg
