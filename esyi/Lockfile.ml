type t = {
  rootDependenciesHash : string;
  solution : Solution.t;
} [@@deriving (yojson)]

let dependenciesHash (manifest : PackageJson.t) =
  let hashDependencies ~prefix ~dependencies digest =
    let f digest req =
     Digest.string (digest ^ "__" ^ prefix ^ "__" ^ PackageInfo.Req.toString req)
    in
    List.fold_left
      ~f ~init:digest
      dependencies
  in
  let digest =
    Digest.string ""
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
    let%bind lockfile = RunAsync.ofRun (Json.parseJsonWith of_yojson json) in
    if lockfile.rootDependenciesHash = dependenciesHash manifest
    then return (Some lockfile.solution)
    else return None
  else
    return None

let toFile ~(manifest : PackageJson.t) ~(solution : Solution.t) (path : Path.t) =
  let rootDependenciesHash = dependenciesHash manifest in
  let lockfile = {rootDependenciesHash; solution} in
  let json = to_yojson lockfile in
  Fs.writeJsonFile ~json path
