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

type id = PackageId.t
type pkg = Package.t
type traverse = pkg -> id list
type t

val empty : id -> t
val add : pkg -> t -> t
val nodes : t -> pkg list

val root : t -> pkg
val isRoot : pkg -> t -> bool
val dependencies : ?traverse:traverse -> pkg -> t -> pkg list
val get : id -> t -> pkg option
val getExn : id -> t -> pkg
val findBy : (id -> pkg -> bool) -> t -> (id * pkg) option
val allDependenciesBFS :
  ?traverse:traverse
  -> ?dependencies:id list
  -> id
  -> t
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

