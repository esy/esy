open EsyPackageConfig

(**
 * This module represents a solution.
 *)

module DepSpec : sig
  type id
  (** Package id. *)

  val root : id
  val self : id

  type t
  (** Dependency expression, *)

  val package : id -> t
  (** [package id] refers to a package by its [id]. *)

  val dependencies : id -> t
  (** [dependencies id] refers all dependencies of the package with [id]. *)

  val devDependencies : id -> t
  (** [dependencies id] refers all devDependencies of the package with [id]. *)

  val (+) : t -> t -> t
  (** [a + b] refers to all packages in [a] and in [b]. *)

  val compare : t -> t -> int
  val pp : t Fmt.t
end

module Spec : sig

  type t = {

    (**
      Define how we traverse packages.
      *)
    all: DepSpec.t;

    (**
      Define how we traverse packages "in-dev".
      *)
    dev : DepSpec.t;
  }

  val everything : t

end

type id = PackageId.t
type pkg = Package.t
type traverse = pkg -> id list
type t

val empty : id -> t
val add : t -> pkg -> t
val nodes : t -> pkg list

val root : t -> pkg
val isRoot : t -> pkg -> bool
val dependencies : t -> Spec.t -> pkg -> pkg list
val get : t -> id -> pkg option
val getExn : t -> id -> pkg
val findBy : t -> (id -> pkg -> bool) -> (id * pkg) option
val allDependenciesBFS :
  ?traverse:traverse
  -> ?dependencies:id list
  -> t
  -> id
  -> (bool * pkg) list
val fold : f:(pkg -> pkg list -> 'v -> 'v) -> init:'v -> t -> 'v

val findByPath : DistPath.t -> t -> pkg option
val findByName : string -> t -> pkg option
val findByNameVersion : string -> Version.t -> t -> pkg option

val traverse : pkg -> id list
val traverseWithDevDependencies : pkg -> id list

val eval : t -> PackageId.t -> DepSpec.t -> PackageId.Set.t
(**
 * [eval solution self depspec] evals [depspec] given the [solution] and the
 * current package id [self].
 *)

val collect : t -> DepSpec.t -> PackageId.t -> PackageId.Set.t
(**
 * [collect solution depspec id] collects all package ids found in the
 * [solution] starting with [id] using [depspec] expression for traverse.
 *)

