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
  resolutions : Package.Resolutions.t;
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
  -> resolutions:Package.Resolutions.t
  -> unit
  -> t RunAsync.t

(** Add dependencies to the solver *)
val add :
  dependencies:Package.Dependencies.t
  -> t
  -> t RunAsync.t

(**
 * Solve dependencies for the root
 *)
val solve :
  cfg:Config.t
  -> resolutions:Package.Resolutions.t
  -> Package.t
  -> Solution.t RunAsync.t
