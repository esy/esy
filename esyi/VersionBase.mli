module type VERSION  = sig
  type t
  val equal : t -> t -> bool
  val compare : t -> t -> int
  val show : t -> string
  val pp : Format.formatter -> t -> unit
  val parse : string -> (t, string) result
  val prerelease : t -> bool
  val stripPrerelease : t -> t
  val toString : t -> string
  val to_yojson : t -> Json.t
  val of_yojson : Json.t -> (t, string) result
end

module type CONSTRAINT = sig
  type version
  type t =
      EQ of version
    | NEQ of version
    | GT of version
    | GTE of version
    | LT of version
    | LTE of version
    | NONE
    | ANY

  module VersionSet : Set.S with type elt = version

  val to_yojson : t Json.encoder
  val of_yojson : t Json.decoder

  val equal : t -> t -> bool
  val compare : t -> t -> int

  val pp : Format.formatter -> t -> unit

  val matchesSimple :
    version:version
    -> t
    -> bool

  val matches :
    ?matchPrerelease:VersionSet.t
    -> version:version
    -> t -> bool

  val toString : t -> string

  val show : t -> string

  val map : f:(version -> version) -> t -> t
end

module type FORMULA = sig
  type version
  type constr

  type 'f conj = 'f list
  type 'f disj = 'f list

  module DNF : sig
    type t = constr disj disj
    val to_yojson : t Json.encoder
    val of_yojson : t Json.decoder
    val equal : t -> t -> bool
    val compare : t -> t -> int
    val unit : 'a -> 'a disj disj
    val matches : version:version -> t -> bool
    val pp : t Fmt.t
    val show : t -> string
    val toString : t -> string
    val map : f:(version -> version) -> t -> t

    val conj : t -> t -> t
    val disj : constr disj -> constr disj -> constr disj
  end

  module CNF : sig
    type t = constr disj conj
    val to_yojson : t Json.encoder
    val of_yojson : t Json.decoder
    val pp : t Fmt.t
    val show : t -> string
    val toString : t -> string
    val matches : version:version -> constr disj disj -> bool
  end

  val ofDnfToCnf : DNF.t -> CNF.t

  module Parse : sig
    val conjunction : parse:(string -> 'a) -> string -> 'a disj
    val disjunction : parse:(string -> constr disj) -> string -> constr disj disj
  end
end

module Constraint : sig
  module Make : functor
    (Version : VERSION)
    -> CONSTRAINT with type version = Version.t
end

module Formula : sig
  module Make : functor
    (Version : VERSION)
    (Constraint : CONSTRAINT with type version = Version.t)
    -> FORMULA with type version = Version.t and type constr = Constraint.t
end
