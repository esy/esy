open EsyPackageConfig

type t = {
  solveRoot : DepSpec.t;
  solveLink : DepSpec.t;
  solveAll : DepSpec.t;
} [@@deriving ord, yojson]

let eval spec root manifest =
  let depspec =
    let isRoot = InstallManifest.compare root manifest = 0 in
    if isRoot
    then spec.solveRoot
    else
      match manifest.InstallManifest.source with
      | PackageSource.Link _ -> spec.solveLink
      | _ -> spec.solveAll
  in
  DepSpec.eval manifest depspec

