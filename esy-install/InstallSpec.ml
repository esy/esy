open EsyPackageConfig

type t = {
  installDev : DepSpec.t;
  installAll : DepSpec.t;
} [@@deriving ord]

let eval solution self spec =
  let depspec =
    match self.Package.source with
    | Link {kind = LinkDev; _} -> spec.installDev
    | Link {kind = LinkRegular; _}
    | Install _ -> spec.installAll
  in
  DepSpec.eval solution self.id depspec

let dependencies solution self spec =
  let ids = eval solution self spec in
  List.map
    ~f:(fun id -> Solution.getExn id solution)
    (PackageId.Set.elements ids)
