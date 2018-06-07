type t

type override

let getOverrides : Fpath.t => RunAsync.t(t);

let findApplicableOverride :
  (t, OpamFile.PackageName.t, OpamVersion.Version.t)
  => RunAsync.t(option(override))

let applyOverride : (OpamFile.manifest, override) => OpamFile.manifest;
