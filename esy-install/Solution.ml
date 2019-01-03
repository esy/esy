open EsyPackageConfig

module DepSpec = struct
  module Id = struct
    type t =
      | Self
      | Root
      [@@deriving ord]

    let pp fmt = function
      | Self -> Fmt.unit "self" fmt ()
      | Root -> Fmt.unit "root" fmt ()
  end

  include DepSpecAst.Make(Id)

  let root = Id.Root
  let self = Id.Self
end

let traverse pkg =
  PackageId.Set.elements pkg.Package.dependencies

let traverseWithDevDependencies pkg =
  let dependencies =
    PackageId.Set.union
      pkg.Package.dependencies
      pkg.Package.devDependencies
  in
  PackageId.Set.elements dependencies

include Graph.Make(struct
  include Package
  let traverse = traverse
  let id pkg = pkg.id
  module Id = PackageId
end)

type pkg = Package.t

let resolve solution self id =
  match id with
  | DepSpec.Id.Root -> (root solution).id
  | DepSpec.Id.Self -> self

let eval solution self depspec =
  let resolve id = resolve solution self id in
  let rec eval' expr =
    match expr with
    | DepSpec.Package id -> PackageId.Set.singleton (resolve id)
    | DepSpec.Dependencies id ->
      let pkg = getExn (resolve id) solution in
      pkg.dependencies
    | DepSpec.DevDependencies id ->
      let pkg = getExn (resolve id) solution in
      pkg.devDependencies
    | DepSpec.Union (a, b) -> PackageId.Set.union (eval' a) (eval' b)
  in
  eval' depspec

let rec collect' solution depspec seen id =
  if PackageId.Set.mem id seen
  then seen
  else
    let f nextid seen = collect' solution depspec seen nextid in
    let seen = PackageId.Set.add id seen in
    let seen = PackageId.Set.fold f (eval solution id depspec) seen in
    seen

let collect solution depspec root =
  collect' solution depspec PackageId.Set.empty root

let findByPath p solution =
  let open Option.Syntax in
  let f _id pkg =
    match pkg.Package.source with
    | Link {path; manifest = None; kind = _; } ->
      let path = DistPath.(path / "package.json") in
      DistPath.compare path p = 0
    | Link {path; manifest = Some filename; kind = _;} ->
      let path = DistPath.(path / ManifestSpec.show filename) in
      DistPath.compare path p = 0
    | _ -> false
  in
  let%map _id, pkg = findBy f solution in
  pkg

let findByName name solution =
  let open Option.Syntax in
  let f _id pkg =
    String.compare pkg.Package.name name = 0
  in
  let%map _id, pkg = findBy f solution in
  pkg

let findByNameVersion name version solution =
  let open Option.Syntax in
  let compare = [%derive.ord: string * Version.t] in
  let f _id pkg =
    compare (pkg.Package.name, pkg.Package.version) (name, version) = 0
  in
  let%map _id, pkg = findBy f solution in
  pkg
