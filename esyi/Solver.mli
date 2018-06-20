(**
 * Package dependency solver.
 *)

module Strategy : sig
  type t
  val trendy : t
end

(** Explanation for solve failure *)
module Explanation : sig
  type t
  val pp : Format.formatter -> t -> unit
end

(** Solver *)
type t = private {
  cfg: Config.t;
  resolver: Resolver.t;
  universe: Universe.t;
}

(**
 * Result of the solver
 *
 * It's either a set of packages to be installed or a failure with a (possibly
 * empty) explanation.
 *)
type solveResult = (Package.Set.t, Explanation.t) result

(** Make new solver given the root package as a seed *)
val make :
  cfg:Config.t
  -> ?resolver:Resolver.t
  -> resolutions:PackageInfo.Resolutions.t
  -> Package.t
  -> t RunAsync.t

(** Solve dependencies *)
val solve :
  ?strategy:Strategy.t
  -> root:Package.t
  -> t
  -> solveResult RunAsync.t
