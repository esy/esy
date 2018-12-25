(**
 * Package dependency solver.
 *)

open EsyPackageConfig

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
  resolutions : Resolutions.t;
}

(**
 * Result of the solver
 *
 * It's either a solution or a failure with a (possibly empty) explanation.
 *)
(** Make new solver *)
val make :
  cfg:Config.t
  -> resolver:Resolver.t
  -> resolutions:Resolutions.t
  -> unit
  -> t RunAsync.t

(** Add dependencies to the solver *)
val add :
  dependencies:InstallManifest.Dependencies.t
  -> t
  -> (t * InstallManifest.Dependencies.t) RunAsync.t

(**
 * Solve dependencies for the root
 *)
val solve : Sandbox.t -> EsyInstall.Solution.t RunAsync.t
