module Version : sig
  type t = {
    major : int;
    minor : int;
    patch : int;
    prerelease : prerelease;
    build : build;
  }
  and prerelease = segment list
  and build = string list
  and segment = W of string | N of int

  include VersionBase.VERSION with type t := t

  val parse : string -> (t, string) result
  val sexp_of_t : t -> Sexplib0.Sexp.t
end

module Constraint :
  VersionBase.CONSTRAINT
  with type version = Version.t

module Formula : sig

  include VersionBase.FORMULA
    with type version = Version.t
    and type constr = Constraint.t

  val any : DNF.t

  val parserDnf : DNF.t Parse.t

  val parse : string -> (DNF.t, string) result
  val parseExn : string -> DNF.t
end

val caretRangeOfVersion : Version.t -> Formula.DNF.t
