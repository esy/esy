module Cache : sig
  type t
  val make : cfg:Config.t -> unit -> t RunAsync.t
end

type t = {
  cfg: Config.t;
  cache: Cache.t;
  mutable universe: Universe.t;
}

val solve :
  cfg:Config.t
  -> resolutions:PackageInfo.Resolutions.t
  -> Package.t
  -> Solution.t RunAsync.t

val initState :
  cfg:Config.t
  -> ?cache:Cache.t
  -> resolutions:PackageInfo.Resolutions.t
  -> Package.t
  -> t RunAsync.t
