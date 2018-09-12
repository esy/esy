type t = kind * string

and kind =
  | Md5
  | Sha1
  | Sha256
  | Sha512

val equal : t -> t -> bool
val compare : t -> t -> int
val pp : t Fmt.t
val show : t -> string

val parser : t Parse.t
val parse : string -> (t, string) result

val to_yojson : t Json.encoder
val of_yojson : t Json.decoder

val checkFile : path:Path.t -> t -> unit RunAsync.t
