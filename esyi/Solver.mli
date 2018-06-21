(**
 * Package dependency solver.
 *)

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
  resolutions : PackageInfo.Resolutions.t;
}

(**
 * Result of the solver
 *
 * It's either a solution or a failure with a (possibly empty) explanation.
 *)
(** Make new solver *)
val make :
  cfg:Config.t
  -> ?resolver:Resolver.t
  -> resolutions:PackageInfo.Resolutions.t
  -> unit
  -> t RunAsync.t

(** Add dependencies to the solver *)
val add :
  dependencies:PackageInfo.Dependencies.t
  -> t
  -> (t * PackageInfo.Dependencies.t) RunAsync.t

(**
 * Solve dependencies for the root
 *)
val solve :
  cfg:Config.t
  -> resolutions:PackageInfo.Resolutions.t
  -> Package.t
  -> Solution.t RunAsync.t
