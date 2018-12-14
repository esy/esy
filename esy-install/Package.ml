type t = {
  id : PackageId.t;
  name: string;
  version: Version.t;
  source: PackageSource.t;
  overrides: Overrides.t;
  dependencies : PackageId.Set.t;
  devDependencies : PackageId.Set.t;
}

let compare a b =
  PackageId.compare a.id b.id

let pp fmt pkg =
  Fmt.pf fmt "%s@%a" pkg.name Version.pp pkg.version

let show = Format.asprintf "%a" pp

module Map = Map.Make(struct type nonrec t = t let compare = compare end)
module Set = Set.Make(struct type nonrec t = t let compare = compare end)
