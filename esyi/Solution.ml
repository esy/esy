module Dependencies = PackageInfo.Dependencies
module Version = PackageInfo.Version
module Source = PackageInfo.Source
module Req = PackageInfo.Req

module Record = struct
  type t = {
    name: string ;
    version: Version.t ;
    source: Source.t ;
    opam: PackageInfo.OpamInfo.t option;
  } [@@deriving yojson]

  let ofPkg (pkg : Package.t) = {
    name = pkg.name;
    version = pkg.version;
    source = pkg.source;
    opam = pkg.opam;
  }

  let compare a b =
    let c = String.compare a.name b.name in
    if c = 0
    then Version.compare a.version b.version
    else c

  let equal a b =
    String.equal a.name b.name && Version.equal a.version b.version

  let pp fmt record =
    Fmt.pf fmt "%s@%a" record.name Version.pp record.version

  module Map = Map.Make(struct type nonrec t = t let compare = compare end)
  module Set = Set.Make(struct type nonrec t = t let compare = compare end)
end

type t = root
[@@deriving yojson]

(**
 * This represent an isolated dependency root.
 *)
and root = {
  record: Record.t;
  dependencies: root list;
}

and lockfile = {
  rootDependenciesHash : string;
  solution : t;
}

let make record dependencies =
  {record = Record.ofPkg record; dependencies}

let record root = root.record
let dependencies root = root.dependencies

let fold ~f ~init solution =
  let rec aux v root =
    let v = List.fold_left ~f:aux ~init:v root.dependencies in
    let v = f v root.record in
    v
  in
  aux init solution

let dependenciesHash (manifest : Manifest.Root.t) =
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
      ~resolutions:manifest.Manifest.Root.resolutions
    |> hashDependencies
      ~prefix:"dependencies"
      ~dependencies:(Dependencies.toList manifest.manifest.dependencies)
    |> hashDependencies
      ~prefix:"devDependencies"
      ~dependencies:(Dependencies.toList manifest.manifest.devDependencies)
  in
  Digest.to_hex digest

let mapSourceLocalPath ~f solution =
  let mapRecord (record : Record.t) =
    let version =
      match record.version with
      | Version.Source (Source.LocalPath p) ->
        Version.Source (Source.LocalPath (f p))
      | Version.Npm _
      | Version.Opam _
      | Version.Source _ -> record.version
    in
    let source =
      match record.source with
      | Source.LocalPath p ->
        Source.LocalPath (f p)
      | Source.Archive _
      | Source.Git _
      | Source.Github _
      | Source.NoSource -> record.source
    in
    {record with source; version}
  in
  let rec mapRoot root = {
    record = mapRecord root.record;
    dependencies = List.map ~f:mapRoot root.dependencies;
  }
  in
  mapRoot solution

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

let ofFile ~cfg ~(manifest : Manifest.Root.t) (path : Path.t) =
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

let toFile ~cfg ~(manifest : Manifest.Root.t) ~(solution : t) (path : Path.t) =
  let solution = relativize ~cfg solution in
  let rootDependenciesHash = dependenciesHash manifest in
  let lockfile = {rootDependenciesHash; solution} in
  let json = lockfile_to_yojson lockfile in
  Fs.writeJsonFile ~json path
