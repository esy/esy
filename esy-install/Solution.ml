module Override = struct
  type t =
    | OfJson of {json : Json.t;}
    | OfDist of {dist : Dist.t; json : Json.t;}
    | OfOpamOverride of {
        path : Path.t;
        json : Json.t;
      }

  module BuildType = struct
    include EsyLib.BuildType
    include EsyLib.BuildType.AsInPackageJson
  end

  type build = {
    buildType : BuildType.t option [@default None] [@key "buildsInSource"];
    build : PackageConfig.CommandList.t option [@default None];
    install : PackageConfig.CommandList.t option [@default None];
    exportedEnv: PackageConfig.ExportedEnv.t option [@default None];
    exportedEnvOverride: PackageConfig.ExportedEnvOverride.t option [@default None];
    buildEnv: PackageConfig.Env.t option [@default None];
    buildEnvOverride: PackageConfig.EnvOverride.t option [@default None];
  } [@@deriving of_yojson { strict = false }]

  type install = {
    dependencies : PackageConfig.NpmFormulaOverride.t option [@default None];
    devDependencies : PackageConfig.NpmFormulaOverride.t option [@default None];
    resolutions : PackageConfig.Resolution.resolution StringMap.t option [@default None];
  } [@@deriving of_yojson { strict = false }]

  let pp fmt = function
    | OfJson _ -> Fmt.unit "<inline override>" fmt ()
    | OfDist {dist; json = _;} -> Fmt.pf fmt "override:%a" Dist.pp dist
    | OfOpamOverride info -> Fmt.pf fmt "opam-override:%a" Path.pp info.path

  let json override =
    let open RunAsync.Syntax in
    match override with
    | OfJson info -> return info.json
    | OfDist info -> return info.json
    | OfOpamOverride info -> return info.json

  let build override =
    let open RunAsync.Syntax in
    let%bind json = json override in
    let%bind override = RunAsync.ofStringError (build_of_yojson json) in
    return (Some override)

  let install override =
    let open RunAsync.Syntax in
    let%bind json = json override in
    let%bind override = RunAsync.ofStringError (install_of_yojson json) in
    return (Some override)

  let ofJson json = OfJson {json;}
  let ofDist json dist = OfDist {json; dist;}

  let files cfg sandbox override =
    let open RunAsync.Syntax in

    match override with
    | OfJson _ -> return []
    | OfDist info ->
      let%bind path = DistStorage.fetchIntoCache ~cfg ~sandbox info.dist in
      File.ofDir Path.(path / "files")
    | OfOpamOverride info ->
      File.ofDir Path.(info.path / "files")

end

module Overrides = struct
  type t = Override.t list

  let empty = []

  let isEmpty = function
    | [] -> true
    | _ -> false

  let add override overrides =
    override::overrides

  let addMany newOverrides overrides =
    newOverrides @ overrides

  let merge newOverrides overrides =
    newOverrides @ overrides

  let fold' ~f ~init overrides =
    RunAsync.List.foldLeft ~f ~init (List.rev overrides)

  let foldWithBuildOverrides ~f ~init overrides =
    let open RunAsync.Syntax in
    let f v override =
      Logs_lwt.debug (fun m -> m "build override: %a" Override.pp override);%lwt
      match%bind Override.build override with
      | Some override -> return (f v override)
      | None -> return v
    in
    fold' ~f ~init overrides

  let foldWithInstallOverrides ~f ~init overrides =
    let open RunAsync.Syntax in
    let f v override =
      Logs_lwt.debug (fun m -> m "install override: %a" Override.pp override);%lwt
      match%bind Override.install override with
      | Some override -> return (f v override)
      | None -> return v
    in
    fold' ~f ~init overrides

  let files cfg sandbox overrides =
    let open RunAsync.Syntax in
    let f files override =
      let%bind filesOfOverride = Override.files cfg sandbox override in
      return (filesOfOverride @ files)
    in
    fold' ~f ~init:[] overrides
end

module Package = struct

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

let findByPath p solution =
  let open Option.Syntax in
  let f _id pkg =
    match pkg.Package.source with
    | Link {path; manifest = None;} ->
      let path = DistPath.(path / "package.json") in
      DistPath.compare path p = 0
    | Link {path; manifest = Some filename;} ->
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
