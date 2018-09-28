type t = kind * string

and kind =
  | Md5
  | Sha1
  | Sha256
  | Sha512

include S.JSONABLE with type t := t
include S.PRINTABLE with type t := t
include S.COMPARABLE with type t := t

val sexp_of_t : t -> Sexplib0.Sexp.t
val parser : t Parse.t
val parse : string -> (t, string) result

val checkFile : path:Path.t -> t -> unit RunAsync.t
