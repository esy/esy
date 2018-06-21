module Version = PackageInfo.Version
module Source = PackageInfo.Source
module Dependencies = PackageInfo.Dependencies

type t = {
  name : string;
  version : PackageInfo.Version.t;
  source : PackageInfo.Source.t;
  dependencies: (Dependencies.t [@default Dependencies.empty]);
  buildDependencies: (Dependencies.t [@default Dependencies.empty]);
  devDependencies: (Dependencies.t [@default Dependencies.empty]);
  opam : PackageInfo.OpamInfo.t option;
}

let ofOpam ?name ?version (manifest : OpamFile.manifest) =
  let open Run.Syntax in
  let name =
    match name with
    | Some name -> name
    | None -> OpamFile.PackageName.toNpm manifest.name
  in
  let version =
    match version with
    | Some version -> version
    | None -> Version.Opam manifest.version
  in
  let source =
    match version with
    | Version.Source (Source.Github (user, name, ref)) ->
      Source.Github (user, name, ref)
    | Version.Source (Source.LocalPath path)  ->
      Source.LocalPath path
    | _ -> manifest.source
  in
  return {
    name;
    version;
    dependencies = manifest.dependencies;
    buildDependencies = manifest.buildDependencies;
    devDependencies = manifest.devDependencies;
    source;
    opam = Some (OpamFile.toPackageJson manifest version);
  }

let ofPackageJson ?name ?version (manifest : PackageJson.t) =
  let open Run.Syntax in
  let name =
    match name with
    | Some name -> name
    | None -> manifest.name
  in
  let version =
    match version with
    | Some version -> version
    | None -> Version.Npm (PackageJson.Version.parseExn manifest.version)
  in
  let%bind source =
    match version with
    | Version.Source (Source.Github (user, name, ref)) ->
      Run.return (Source.Github (user, name, ref))
    | Version.Source (Source.LocalPath path)  ->
      Run.return (Source.LocalPath path)
    | _ -> begin
      match manifest.dist with
      | Some dist -> return (Source.Archive (dist.tarball, dist.shasum))
      | None ->
        let msg =
          Printf.sprintf
            "source cannot be found for %s@%s"
            manifest.name manifest.version
        in
        error msg
      end
  in
  return {
    name;
    version;
    dependencies = manifest.dependencies;
    buildDependencies = manifest.buildDependencies;
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
