module Version = PackageInfo.Version
module Source = PackageInfo.Source

type t = {
  name : string;
  version : PackageInfo.Version.t;
  source : PackageInfo.Source.t;
  dependencies: PackageInfo.DependenciesInfo.t;
  opam : PackageInfo.OpamInfo.t option;
}

and manifest =
  | Opam of OpamFile.manifest
  | PackageJson of PackageJson.t

let make ~version manifest =
  let open Run.Syntax in
  let dependencies =
    match manifest with
    | Opam manifest -> OpamFile.dependencies manifest
    | PackageJson manifest -> PackageJson.dependencies manifest
  in
  let%bind source =
    match version with
    | Version.Source (Source.Github (user, name, ref)) ->
      Run.return (PackageInfo.Source.Github (user, name, ref))
    | Version.Source (Source.LocalPath path)  ->
      Run.return (PackageInfo.Source.LocalPath path)
    | _ -> begin
      match manifest with
      | Opam manifest -> return (OpamFile.source manifest)
      | PackageJson json -> PackageJson.source json
    end
  in
  let name =
    match manifest with
    | Opam manifest -> OpamFile.name manifest
    | PackageJson manifest  -> PackageJson.name manifest
  in
  let opam =
    match manifest with
    | Opam manifest ->
      Some (OpamFile.toPackageJson manifest version)
    | PackageJson _ -> None
  in
  return {
    name;
    version;
    dependencies;
    source;
    opam;
  }

let pp fmt pkg =
  Fmt.pf fmt "%s@%a" pkg.name Version.pp pkg.version

let compare pkga pkgb =
  let name = String.compare pkga.name pkgb.name in
  if name = 0
  then Version.compare pkga.version pkgb.version
  else name

module Map = Map.Make(struct
  type nonrec t = t
  let compare = compare
end)

module Set = Set.Make(struct
  type nonrec t = t
  let compare = compare
end)
