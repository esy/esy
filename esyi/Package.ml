module Version = PackageInfo.Version
module Source = PackageInfo.Source
module Dependencies = PackageInfo.Dependencies

type t = {
  name : string;
  version : PackageInfo.Version.t;
  source : PackageInfo.Source.t;
  dependencies: (Dependencies.t [@default Dependencies.empty]);
  devDependencies: (Dependencies.t [@default Dependencies.empty]);
  opam : PackageInfo.OpamInfo.t option;
}

let ofOpamManifest ?name ?version (manifest : OpamManifest.t) =
  let open Run.Syntax in
  let name =
    match name with
    | Some name -> name
    | None -> OpamManifest.PackageName.toNpm manifest.name
  in
  let version =
    match version with
    | Some version -> version
    | None -> Version.Opam manifest.version
  in
  let source =
    match version with
    | Version.Source src -> src
    | _ -> manifest.source
  in
  return {
    name;
    version;
    dependencies = manifest.dependencies;
    devDependencies = manifest.devDependencies;
    source;
    opam = Some (OpamManifest.toPackageJson manifest version);
  }

let ofManifest ?name ?version (manifest : Manifest.t) =
  let open Run.Syntax in
  let name =
    match name with
    | Some name -> name
    | None -> manifest.name
  in
  let version =
    match version with
    | Some version -> version
    | None -> Version.Npm (NpmVersion.Version.parseExn manifest.version)
  in
  let source =
    match version with
    | Version.Source src -> src
    | _ -> manifest.source
  in
  return {
    name;
    version;
    dependencies = manifest.dependencies;
    devDependencies = manifest.devDependencies;
    source;
    opam = None;
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
