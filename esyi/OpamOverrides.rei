type t

type override

let init : (~cfg: Config.t, unit) => RunAsync.t(t);

let get :
  (t, OpamManifest.PackageName.t, OpamVersion.Version.t)
  => RunAsync.t(option(override))

let apply : (OpamManifest.t, override) => OpamManifest.t;
