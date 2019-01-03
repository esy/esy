open EsyPackageConfig

type t = {
  installDev : Solution.DepSpec.t;
  installAll : Solution.DepSpec.t;
} [@@deriving ord]

let eval solution self spec =
  let depspec =
    match self.Package.source with
    | Link {kind = LinkDev; _} -> spec.installDev
    | Link {kind = LinkRegular; _}
    | Install _ -> spec.installAll
  in
  Solution.eval solution self.id depspec

let dependencies solution self spec =
  let ids = eval solution self spec in
  List.map
    ~f:(fun id -> Solution.getExn solution id)
    (PackageId.Set.elements ids)
