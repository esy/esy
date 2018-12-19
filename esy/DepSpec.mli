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

val eval : EsyInstall.Solution.t -> EsyInstall.PackageId.t -> t -> EsyInstall.PackageId.Set.t
(** Eval depspec given the [Solution.t] and the current package [PackageId.t]. *)

val compare : t -> t -> int
val pp : t Fmt.t
