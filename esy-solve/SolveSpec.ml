open EsyPackageConfig

type t = {
  solveDev : DepSpec.t;
  solveAll : DepSpec.t;
} [@@deriving ord]

let eval spec manifest =
  let depspec =
    match manifest.InstallManifest.source with
    | Link {kind = LinkDev; _} -> spec.solveDev
    | Link {kind = LinkRegular; _}
    | Install _ -> spec.solveAll
  in
  DepSpec.eval manifest depspec

