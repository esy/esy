module Version = PackageInfo.Version
module Source = PackageInfo.Source
module Req = PackageInfo.Req

type t = {
  root: pkg;
  dependencies: pkg list;
}
[@@deriving yojson]

and pkg = {
  name: string ;
  version: Version.t ;
  source: Source.t ;
  opam: (PackageInfo.OpamInfo.t option [@default None])
}

and lockfile = {
  rootDependenciesHash : string;
  solution : t;
}

let make ~root ~dependencies =
  let makePkg (pkg : Package.t) = {
    name = pkg.name;
    version = pkg.version;
    source = pkg.source;
    opam = pkg.opam
  } in
  let root = makePkg root in
  let dependencies =
    dependencies
    |> Package.Set.elements
    |> List.map ~f:makePkg
  in
  {root; dependencies}

let packages solution = solution.dependencies

let dependenciesHash (manifest : PackageJson.t) =
  let hashDependencies ~prefix ~dependencies digest =
    let f digest req =
     Digest.string (digest ^ "__" ^ prefix ^ "__" ^ Req.toString req)
    in
    List.fold_left
      ~f ~init:digest
      dependencies
  in
  let hashResolutions ~resolutions digest =
    let f digest (key, version) =
     Digest.string (digest ^ "__" ^ key ^ "__" ^ Version.toString version)
    in
    List.fold_left
      ~f ~init:digest
      (PackageInfo.Resolutions.entries resolutions)
  in
  let digest =
    Digest.string ""
    |> hashResolutions
      ~resolutions:manifest.PackageJson.resolutions
    |> hashDependencies
      ~prefix:"dependencies"
      ~dependencies:manifest.PackageJson.dependencies
    |> hashDependencies
      ~prefix:"buildDependencies"
      ~dependencies:manifest.PackageJson.buildDependencies
    |> hashDependencies
      ~prefix:"devDependencies"
      ~dependencies:manifest.PackageJson.devDependencies
  in
  Digest.to_hex digest

let mapSourceLocalPath ~f solution =
  let mapPkg (pkg : pkg) =
    let version =
      match pkg.version with
      | Version.Source (Source.LocalPath p) ->
        Version.Source (Source.LocalPath (f p))
      | Version.Npm _
      | Version.Opam _
      | Version.Source _ -> pkg.version
    in
    let source =
      match pkg.source with
      | Source.LocalPath p ->
        Source.LocalPath (f p)
      | Source.Archive _
      | Source.Git _
      | Source.Github _
      | Source.NoSource -> pkg.source
    in
    {pkg with source; version}
  in
  {
    root = mapPkg solution.root;
    dependencies = List.map ~f:mapPkg solution.dependencies;
  }

let relativize ~cfg sol =
  let f path =
    if Path.equal path cfg.Config.basePath
    then Path.(v ".")
    else match Path.relativize ~root:cfg.Config.basePath path with
    | Some path -> path
    | None -> path
  in
  mapSourceLocalPath ~f sol

let derelativize ~cfg sol =
  let f path = Path.append cfg.Config.basePath path in
  mapSourceLocalPath ~f sol

let ofFile ~cfg ~(manifest : PackageJson.t) (path : Path.t) =
  let open RunAsync.Syntax in
  if%bind Fs.exists path
  then
    let%bind json = Fs.readJsonFile path in
    let%bind lockfile = RunAsync.ofRun (Json.parseJsonWith lockfile_of_yojson json) in
    if lockfile.rootDependenciesHash = dependenciesHash manifest
    then
      let solution = derelativize ~cfg lockfile.solution in
      return (Some solution)
    else return None
  else
    return None

let toFile ~cfg ~(manifest : PackageJson.t) ~(solution : t) (path : Path.t) =
  let solution = relativize ~cfg solution in
  let rootDependenciesHash = dependenciesHash manifest in
  let lockfile = {rootDependenciesHash; solution} in
  let json = lockfile_to_yojson lockfile in
  Fs.writeJsonFile ~json path
