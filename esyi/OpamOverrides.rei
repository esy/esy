type t

type override

let init : (~cfg: Config.t, unit) => RunAsync.t(t);

let get :
  (t, OpamFile.PackageName.t, OpamVersion.Version.t)
  => RunAsync.t(option(override))

let apply : (OpamFile.manifest, override) => OpamFile.manifest;
