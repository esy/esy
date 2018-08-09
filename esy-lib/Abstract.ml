module type PRINTABLE = sig
  type t

  val pp : t Fmt.t
  val show : t -> string
  val toString : t -> string
end

module type JSONABLE = sig
  type t

  val to_yojson : t Json.encoder
  val of_yojson : t Json.decoder
end

module type COMPARABLE = sig
  type t

  val equal : t -> t -> bool
  val compare : t -> t -> int
end

module type COMMON = sig
  type t

  include COMPARABLE with type t := t
  include PRINTABLE with type t := t
  include JSONABLE with type t := t
end

