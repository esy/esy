module Version : sig
  include VersionBase.VERSION with type t = OpamPackage.Version.t

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

