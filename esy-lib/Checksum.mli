type t =
  | Md5 of string
  | Sha1 of string

val equal : t -> t -> bool
val compare : t -> t -> int
val pp : t Fmt.t
val show : t -> string
val parse : string -> (t, string) result

val to_yojson : t Json.encoder
val of_yojson : t Json.decoder
