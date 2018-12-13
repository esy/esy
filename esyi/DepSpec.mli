(** Dependency specification language *)

module type DEPSPEC = sig
  type id

  type t =
    private
    | Package of id
    | Dependencies of id
    | DevDependencies of id
    | Union of t * t
  (* term *)

  val package : id -> t
  (* refer to a package defined by source *)

  val dependencies : id -> t
  (* refer to dependencies defined by source *)

  val devDependencies : id -> t
  (* refer to devDependencies defined by source *)

  val union : t -> t -> t
  (** [union a b] produces a new term with all packages defined by [a] and * [b] *)

  val (+) : t -> t -> t
  (** [a + b] is the same as [union a b] *)

  val compare : t -> t -> int
  val pp : Format.formatter -> t -> unit
end

module type ID = sig
  type t

  val compare : t -> t -> int
  val pp : Format.formatter -> t -> unit
end

module Make (Id : ID) : DEPSPEC with type id = Id.t
