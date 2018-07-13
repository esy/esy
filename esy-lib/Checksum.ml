type t =
| Md5 of string
| Sha1 of string
[@@deriving eq, ord]

let pp fmt v =
  match v with
  | Md5 v -> Fmt.pf fmt "md5:%s" v
  | Sha1 v -> Fmt.pf fmt "sha1:%s" v

let show v =
  match v with
  | Md5 v -> "md5:" ^ v
  | Sha1 v -> "sha1:" ^ v

let parse v =
  match Astring.String.cut ~sep:":" v with
  | Some ("md5", v) -> Ok (Md5 v)
  | Some ("sha1", v) -> Ok (Sha1 v)
  | Some (kind, _) -> Error ("unknown checkum kind: " ^ kind)
  | None -> Ok (Sha1 v)

let to_yojson v = `String (show v)
let of_yojson json =
  match json with
  | `String v -> parse v
  | _ -> Error "expected string"
