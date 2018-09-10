(**
 * This module defines utilities for working with versions.
 *)

(**
 * Type for versions.
 *
 * opam's versions and npm's semver versions implement this.
 *)
module type VERSION  = sig
  type t

  include S.COMMON with type t := t

  val parser : t Parse.t
  val parse : string -> (t, string) result
  val parseExn : string -> t

  val majorMinorPatch : t -> (int * int * int) option
  val prerelease : t -> bool
  val stripPrerelease : t -> t
end

(**
 * Constraints over versions.
 *)
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

  include S.COMMON with type t := t

  module VersionSet : Set.S with type elt = version

  val matchesSimple :
    version:version
    -> t
    -> bool

  val matches :
    ?matchPrerelease:VersionSet.t
    -> version:version
    -> t -> bool

  val map : f:(version -> version) -> t -> t
end

(**
 * Formulas over constraints.
 *)
module type FORMULA = sig
  type version
  type constr

  type 'f conj = 'f list
  type 'f disj = 'f list

  (**
   * Disjnuction normal form.
   *)
  module DNF : sig
    type t = constr conj disj

    include S.COMMON with type t := t

    val unit : constr -> t
    val matches : version:version -> t -> bool
    val map : f:(version -> version) -> t -> t

    val conj : t -> t -> t
    val disj : constr disj -> constr disj -> constr disj
  end

  (**
   * Conjunction normal form.
   *)
  module CNF : sig
    type t = constr disj conj

    include S.COMMON with type t := t

    val matches : version:version -> constr disj disj -> bool
  end

  (**
   * Convert from DNF to CNF.
   *)
  val ofDnfToCnf : DNF.t -> CNF.t

  module ParseUtils : sig
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
