module Version : sig
  type t =
    { major : int;
      minor : int;
      patch : int;
      prerelease : prerelease_id list;
      build : string list }

  and prerelease_id = N of int | A of string

  val compare : t -> t -> int
  (** Compare two versions. *)

  val parse : string -> (t, string) result
  (** Parse a string into a semver version. *)

  val parse_exn : string -> t
  (** Like {!parse} but raises if it cannot parse. *)

  val pp : Format.formatter -> t -> unit
  (** Pretty-printer for semvers. *)

  val show : t -> string
  (** Convert a semver to a string. *)

  val pp_inspect : Format.formatter -> t -> unit
end

(**
 * Represents dependency formulats over [Version.t].
 *)
module Formula : sig
  type t = range list
  (**
   * A dependency formula is a DNF but with some advanced range syntax, see
   * [N.t] for a representation which have all advanced syntax desugared.
   *)

  and range =
    | Hyphen of version_or_pattern * version_or_pattern  (** V1 - V2 *)
    | Simple of clause list

  and clause =
    | Patt of version_or_pattern
    | Expr of op * version_or_pattern
    | Spec of spec * version_or_pattern

  and op = GT | GTE | LT | LTE | EQ

  and spec = Tilda | Caret

  and version_or_pattern = Version of Version.t | Pattern of pattern

  and pattern = Any | Major of int | Minor of int * int

  val parse : string -> (t, string) result
  (** Parse a string into a semver formula. *)

  val parse_exn : string -> t
  (** Like {!parse} but raises if it cannot parse. *)

  val pp : Format.formatter -> t -> unit
  (** Pretty-printer for semver formulas. *)

  val show : t -> string
  (** Convert a semver formula to a string. *)

  val satisfies : t -> Version.t -> bool
  (**
   * [satisfies f v] returns [true] if version [v] satisfies formula [f].
   *
   * Note that this doesn't take into account build metadata (+tag), so
   *
   *    1.0.0+build matches =1.0.0
   *    1.0.0+build matches =1.0.0+build2
   *
   *)

  val of_version : Version.t -> t
  (**
   * Create a formula of version. It can only be satisfied by this exact
   * version
   *)

  val any : t
  (**
   * A formula which can be satisfied by any version.
   *)

  (** A simple constraint is an op and a version. *)
  module Constraint : sig
    type t = op * Version.t
  end

  (**
   * DNF - Disjunctive Normal Form.
   *
   * Represents as formula as a set of disjunctions of conjunctions.
   *)
  module DNF : sig
    type t = Constraint.t list list

    val pp : Format.formatter -> t -> unit

    val show : t -> string

    val satisfies : t -> Version.t -> bool
  end

  (**
   * CNF - Conjunctive Normal Form
   *
   * Represents a formula as a set of conjunctions of disjunctions.
   *
   * Note that we don't provide [satisfies : CNF.t -> Version.t -> bool] because
   * semver defines constraint matching in terms of DNF and CNF in relation on
   * how it treats pre-releases.
   *)
  module CNF : sig
    type t = Constraint.t list list

    val pp : Format.formatter -> t -> unit

    val show : t -> string
  end

  val to_dnf : t -> DNF.t
  (** Converts a formula into DNF form. *)

  val to_cnf : t -> CNF.t
  (** Converts a formula into CNF form. *)
end
