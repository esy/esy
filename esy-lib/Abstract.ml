module type COMMON = sig
  type t

  val equal : t -> t -> bool
  val compare : t -> t -> int

  val pp : t Fmt.t
  val show : t -> string
  val toString : t -> string

  val to_yojson : t Json.encoder
  val of_yojson : t Json.decoder
end
