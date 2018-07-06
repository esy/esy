module Version = Package.Version
module Source = Package.Source
module Req = Package.Req

module Record = struct
  type t = {
    name: string;
    version: Version.t;
    source: Source.t;
    files : Package.File.t list;
    manifest : Json.t option;
  } [@@deriving yojson]

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


[@@@ocaml.warning "-32"]
type solution = t [@@deriving (to_yojson, eq)]

and t = root

and root = {
  record: Record.t;
  dependencies: root StringMap.t;
}

let rec pp fmt root =
  let ppItem = Fmt.(pair nop pp) in
  Fmt.pf fmt
    "@[<v 2>%a@\n%a@]"
    Record.pp root.record
    (StringMap.pp ppItem) root.dependencies

let make record dependencies =
  let dependencies =
    let f map (root : t) =
      StringMap.add root.record.name root map
    in
    List.fold_left ~f ~init:StringMap.empty dependencies
  in
  {record; dependencies}

let record root = root.record
let dependencies root = StringMap.values root.dependencies

let findDependency ~name root =
  StringMap.find_opt name root.dependencies

let fold ~f ~init solution =
  let rec aux r root =
    let r = StringMap.fold (fun _k v r -> aux r v) root.dependencies r in
    let r = f r root.record in
    r
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
      (Package.Resolutions.entries resolutions)
  in
  let digest =
    Digest.string ""
    |> hashResolutions
      ~resolutions:manifest.Manifest.Root.resolutions
    |> hashDependencies
      ~prefix:"dependencies"
      ~dependencies:manifest.manifest.dependencies
    |> hashDependencies
      ~prefix:"devDependencies"
      ~dependencies:manifest.manifest.devDependencies
  in
  Digest.to_hex digest

module LockfileV1 = struct


  type t = {
    hash : string;
    root : string;
    node : node StringMap.t
  }

  and node = {
    record : Record.t;
    dependencies : string list;
  } [@@deriving yojson]

  let mapRecord ~f (record : Record.t) =
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
      | Source.LocalPathLink p ->
        Source.LocalPathLink (f p)
      | Source.LocalPath p ->
        Source.LocalPath (f p)
      | Source.Archive _
      | Source.Git _
      | Source.Github _
      | Source.NoSource -> record.source
    in
    {record with source; version}

  let relativizeRecord ~cfg record =
    let f path =
      if Path.equal path cfg.Config.basePath
      then Path.(v ".")
      else match Path.relativize ~root:cfg.Config.basePath path with
      | Some path -> path
      | None -> path
    in
    mapRecord ~f record

  let derelativize ~cfg record =
    let f path = Path.(cfg.Config.basePath // path |> normalize) in
    mapRecord ~f record

  let rec solutionOfLockfile ~cfg nodes id =
    match StringMap.find id nodes with
    | Some {record; dependencies} ->
      let dependencies = List.map ~f:(solutionOfLockfile ~cfg nodes) dependencies in
      let record = derelativize ~cfg record in
      make record dependencies
    | None -> raise (Invalid_argument "malformed lockfile")

  let lockfileOfSolution ~cfg (root : solution) =
    let nodes = StringMap.empty in
    let rec aux nodes root =
      let dependencies, nodes =
        let f (dependencies, nodes) root =
          let id, nodes = aux nodes root in
          (id::dependencies, nodes)
        in
        List.fold_left ~f ~init:([], nodes) (dependencies root)
      in
      let record = record root in
      let record = relativizeRecord ~cfg record in
      let id = Format.asprintf "%s@%a" record.name Version.pp record.version in
      let node = {record; dependencies} in
      let nodes =
        if StringMap.mem id nodes
        then nodes
        else StringMap.add id node nodes
      in
      id, nodes
    in
    aux nodes root

  let ofFile ~cfg ~(manifest : Manifest.Root.t) (path : Path.t) =
    let open RunAsync.Syntax in
    if%bind Fs.exists path
    then
      let%bind json = Fs.readJsonFile path in
      let%bind lockfile = RunAsync.ofRun (Json.parseJsonWith of_yojson json) in
      if lockfile.hash = dependenciesHash manifest
      then
        let solution = solutionOfLockfile ~cfg lockfile.node lockfile.root in
        return (Some solution)
      else return None
    else
      return None

  let toFile ~cfg ~(manifest : Manifest.Root.t) ~(solution : solution) (path : Path.t) =
    let root, node = lockfileOfSolution ~cfg solution in
    let hash = dependenciesHash manifest in
    let lockfile = {hash; node; root} in
    let json = to_yojson lockfile in
    Fs.writeJsonFile ~json path
end
