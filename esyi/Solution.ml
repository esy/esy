type t = {
  root: pkg;
  dependencies: pkg list;
}
[@@deriving yojson]

and pkg = {
  name: string ;
  version: PackageInfo.Version.t ;
  source: PackageInfo.Source.t ;
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
  let dependencies = List.map ~f:makePkg dependencies in
  {root; dependencies}

let packages solution = solution.dependencies

let dependenciesHash (manifest : PackageJson.t) =
  let hashDependencies ~prefix ~dependencies digest =
    let f digest req =
     Digest.string (digest ^ "__" ^ prefix ^ "__" ^ PackageInfo.Req.toString req)
    in
    List.fold_left
      ~f ~init:digest
      dependencies
  in
  let hashResolutions ~resolutions digest =
    let f digest (key, version) =
     Digest.string (digest ^ "__" ^ key ^ "__" ^ PackageInfo.Version.toString version)
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

let ofFile ~(manifest : PackageJson.t) (path : Path.t) =
  let open RunAsync.Syntax in
  if%bind Fs.exists path
  then
    let%bind json = Fs.readJsonFile path in
    let%bind lockfile = RunAsync.ofRun (Json.parseJsonWith lockfile_of_yojson json) in
    if lockfile.rootDependenciesHash = dependenciesHash manifest
    then return (Some lockfile.solution)
    else return None
  else
    return None

let toFile ~(manifest : PackageJson.t) ~(solution : t) (path : Path.t) =
  let rootDependenciesHash = dependenciesHash manifest in
  let lockfile = {rootDependenciesHash; solution} in
  let json = lockfile_to_yojson lockfile in
  Fs.writeJsonFile ~json path
