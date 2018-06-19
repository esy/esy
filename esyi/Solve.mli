module Strategy : sig
  type t
  val trendy : t
end

module Explanation : sig
  type t
  val pp : Format.formatter -> t -> unit
end

type t = {
  cfg: Config.t;
  resolver: Resolver.t;
  mutable universe: Universe.t;
}

type solveResult = (Solution.t, Explanation.t) result

val make :
  cfg:Config.t
  -> ?resolver:Resolver.t
  -> resolutions:PackageInfo.Resolutions.t
  -> Package.t
  -> t RunAsync.t

val solve :
  ?strategy:Strategy.t
  -> root:Package.t
  -> t
  -> solveResult RunAsync.t
